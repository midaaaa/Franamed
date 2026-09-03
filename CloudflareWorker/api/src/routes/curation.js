// Community curation of frames.
//
// The model is "approved by default, hidden by weight": nothing is pre-vetted,
// and an image leaves the playable pool when enough weighted judgement says it
// should. Votes are stored per user rather than as an anonymous counter so a
// vote can be changed — the old weight comes off, the new one goes on.

import { badRequest, json, notFound, parseInteger, readJSON, requireEnum } from "../lib/http.js";
import { authenticate, requireRole } from "../lib/auth.js";
import { DIFFICULTY_TIERS, IMAGE_STATUSES, MEDIA_TYPES, REPORT_REASONS, refreshMediaCounters, serializeImage } from "../lib/media.js";
import { readConfig } from "../lib/config.js";
import { grantBonusAttempts } from "../lib/daily.js";
import { limitByUser, voterWeight } from "../lib/limits.js";

// Recomputes one image's status from the votes and reports on it, then updates
// its title's cached counters. Everything that can change an image's standing
// funnels through here so the derivation lives in exactly one place.
async function recomputeImageStatus(env, imageId) {
    const config = await readConfig(env);

    const image = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
    if (!image) throw notFound("Unknown image");

    const votes = await env.DB.prepare(
        `SELECT
            COALESCE(SUM(CASE WHEN verdict = 'approve' THEN weight ELSE 0 END), 0) AS approve,
            COALESCE(SUM(CASE WHEN verdict = 'reject'  THEN weight ELSE 0 END), 0) AS reject
         FROM image_votes WHERE image_id = ?`
    ).bind(imageId).first();

    const reports = await env.DB.prepare(
        "SELECT COALESCE(SUM(weight), 0) AS weight FROM image_reports WHERE image_id = ?"
    ).bind(imageId).first();

    const net = votes.approve - votes.reject;

    // A moderator verdict is final. Votes and reports still land — they are how
    // a moderator finds out they were wrong — they just stop deciding.
    let status;
    if (image.moderator_status) {
        status = image.moderator_status;
    } else if (reports.weight >= config.autoHideReportWeight) {
        status = "rejected";
    } else if (net <= -1) {
        status = "rejected";
    } else if (net >= 1) {
        status = "approved";
    } else {
        status = "pending";
    }

    await env.DB.prepare("UPDATE media_images SET status = ?, report_weight = ? WHERE id = ?")
        .bind(status, reports.weight, imageId)
        .run();

    await refreshMediaCounters(env, image.media_key);
    return { ...image, status, report_weight: reports.weight };
}

// A verdict on a cluster leader applies to every near-duplicate behind it. The
// point is to save the curator repeated identical judgement calls, never to
// shrink the playable pool — a film shot in one location legitimately has many
// similar frames and all of them stay available.
async function clusterMemberIds(env, image) {
    const leaderPath = image.clustered_with || image.file_path;
    const rows = await env.DB.prepare(
        "SELECT id FROM media_images WHERE media_key = ? AND (file_path = ? OR clustered_with = ?)"
    ).bind(image.media_key, leaderPath, leaderPath).all();
    return rows.results.map((row) => row.id);
}

export async function handleCuration(request, env, segments, url) {
    // GET /v1/curation/queue — what to show a curator next
    if (segments[0] === "queue" && request.method === "GET") {
        const user = await authenticate(request, env);

        const mediaType = url.searchParams.get("mediaType");
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");
        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 20, min: 1, max: 50 });

        // What the queue chases is a title having *enough good frames*, not
        // every frame having been looked at. A popular film can carry 170
        // backdrops; a round uses six. Asking curators to clear all 170 spends
        // their attention on frames no player will ever see.
        //
        // So weight falls away once a title reaches the target approved count,
        // or once there is simply nothing left to approve. It never reaches
        // zero: TMDB keeps adding backdrops, so "done" is never permanent, and
        // the small floor lets a settled title resurface occasionally.
        const config = await readConfig(env);

        const rows = await env.DB.prepare(
            `SELECT i.*, m.title, m.media_type, m.release_year,
                    CASE
                        WHEN m.approved_images >= ?1 THEN 0.001
                        WHEN m.reviewed_images >= m.total_images THEN 0.001
                        ELSE m.popularity * (CAST(?1 - m.approved_images AS REAL) / ?1) + 0.01
                    END AS weight
             FROM media_images i
             JOIN media_items m ON m.key = i.media_key
             WHERE i.status = 'pending'
               AND i.clustered_with IS NULL
               AND (?2 IS NULL OR m.media_type = ?2)
               AND NOT EXISTS (SELECT 1 FROM image_votes v WHERE v.image_id = i.id AND v.uid = ?3)
             ORDER BY weight DESC, RANDOM()
             LIMIT ?4`
        ).bind(config.targetApprovedFrames, mediaType || null, user.uid, limit).all();

        return json({
            items: rows.results.map((row) => ({
                ...serializeImage(row),
                title: row.title,
                releaseYear: row.release_year
            }))
        });
    }

    // POST /v1/curation/vote — binary classification from the curation screen
    if (segments[0] === "vote" && request.method === "POST") {
        const user = await authenticate(request, env);
        const body = await readJSON(request);

        const imageId = Number.parseInt(body.imageId, 10);
        if (!Number.isInteger(imageId)) throw badRequest("imageId must be an integer");
        const verdict = requireEnum(body, "verdict", ["approve", "reject"]);

        const image = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
        if (!image) throw notFound("Unknown image");

        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const config = await readConfig(env);
        // Zero for an account that has not played yet: weighted voting assumes
        // accounts are scarce, and anonymous ones are free.
        const weight = await voterWeight(env, user);
        const isFirstVote = !(await env.DB.prepare("SELECT 1 AS present FROM image_votes WHERE image_id = ? AND uid = ?")
            .bind(imageId, user.uid)
            .first());

        const targets = await clusterMemberIds(env, image);

        await env.DB.batch(
            targets.map((id) =>
                env.DB.prepare(
                    `INSERT INTO image_votes (image_id, uid, verdict, weight, created_at)
                     VALUES (?, ?, ?, ?, ?)
                     ON CONFLICT (image_id, uid) DO UPDATE SET verdict = excluded.verdict, weight = excluded.weight`
                ).bind(id, user.uid, verdict, weight, Date.now())
            )
        );

        const updated = [];
        for (const id of targets) updated.push(serializeImage(await recomputeImageStatus(env, id)));

        // Curating buys attempts. Only a genuinely new vote pays out, so
        // flip-flopping a verdict is not a way to farm the reward.
        if (isFirstVote) await grantBonusAttempts(env, user.uid, config.curationRewardAttempts);

        return json({
            images: updated,
            awardedAttempts: isFirstVote ? config.curationRewardAttempts : 0,
            // Attempts are still earned while the weight is zero — curating is
            // how a new player unlocks more rounds, and blocking that would
            // shut the door on exactly the people we want to onboard.
            voteWeight: weight,
            voteCounts: weight > 0
        });
    }

    // POST /v1/curation/report — the in-round "something is wrong with this frame" button
    if (segments[0] === "report" && request.method === "POST") {
        const user = await authenticate(request, env);
        const body = await readJSON(request);

        const imageId = Number.parseInt(body.imageId, 10);
        if (!Number.isInteger(imageId)) throw badRequest("imageId must be an integer");
        const reason = requireEnum(body, "reason", REPORT_REASONS);

        const image = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
        if (!image) throw notFound("Unknown image");

        await limitByUser(env, user.uid, "WRITE_LIMITER");
        const reportWeight = await voterWeight(env, user);

        await env.DB.prepare(
            `INSERT INTO image_reports (image_id, uid, reason, weight, created_at)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT (image_id, uid) DO UPDATE SET reason = excluded.reason, weight = excluded.weight`
        ).bind(imageId, user.uid, reason, reportWeight, Date.now()).run();

        const updated = await recomputeImageStatus(env, imageId);

        // A replacement is offered for the one-frame mode, where the reported
        // image is the whole round. The round never charges an attempt for
        // this: the player is compensating for broken content, not failing to
        // recognise a film.
        const replacement = await env.DB.prepare(
            "SELECT * FROM media_images WHERE media_key = ? AND status = 'approved' AND id != ? ORDER BY RANDOM() LIMIT 1"
        ).bind(image.media_key, imageId).first();

        return json({
            image: serializeImage(updated),
            replacement: replacement ? serializeImage(replacement) : null
        });
    }

    // POST /v1/curation/images/{id}/lock — a verdict votes cannot overturn
    if (segments[0] === "images" && segments[2] === "lock" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const imageId = Number.parseInt(segments[1], 10);
        if (!Number.isInteger(imageId)) throw badRequest("Image id must be an integer");

        const body = await readJSON(request);
        const lock = body.status === null ? null : requireEnum(body, "status", ["approved", "rejected"]);

        // A later moderator can overturn an earlier one, otherwise the first
        // wrong lock would be permanent. Who locked it is recorded either way.
        await env.DB.prepare(
            "UPDATE media_images SET moderator_status = ?, moderator_uid = ?, moderator_at = ? WHERE id = ?"
        ).bind(lock, lock ? user.uid : null, lock ? Date.now() : null, imageId).run();

        // Setting a tier in the same call saves a round trip: approving a frame
        // and saying how hard it is are one judgement in practice.
        if (body.difficultyTier !== undefined) {
            if (body.difficultyTier !== null && !DIFFICULTY_TIERS.includes(body.difficultyTier)) {
                throw badRequest(`difficultyTier must be null or one of: ${DIFFICULTY_TIERS.join(", ")}`);
            }
            await env.DB.prepare("UPDATE media_images SET difficulty_tier = ? WHERE id = ?")
                .bind(body.difficultyTier, imageId)
                .run();
        }

        return json(serializeImage(await recomputeImageStatus(env, imageId)));
    }

    // POST /v1/curation/images/{id}/dismiss-disputes — "the complaints are wrong"
    if (segments[0] === "images" && segments[2] === "dismiss-disputes" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const imageId = Number.parseInt(segments[1], 10);
        if (!Number.isInteger(imageId)) throw badRequest("Image id must be an integer");

        // The complaints are cleared but the fact that they were cleared is
        // not: a frame dismissed three times still reads as one that keeps
        // attracting them, which is the whole point of keeping the count.
        await env.DB.batch([
            env.DB.prepare("DELETE FROM image_reports WHERE image_id = ?").bind(imageId),
            env.DB.prepare("DELETE FROM image_votes WHERE image_id = ?").bind(imageId),
            env.DB.prepare(
                `UPDATE media_images
                 SET disputes_dismissed_at = ?, disputes_dismissed_count = disputes_dismissed_count + 1
                 WHERE id = ?`
            ).bind(Date.now(), imageId)
        ]);

        return json(serializeImage(await recomputeImageStatus(env, imageId)));
    }

    // GET /v1/curation/contested — locked frames the community disagrees with
    if (segments[0] === "contested" && request.method === "GET") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 50, min: 1, max: 200 });

        const rows = await env.DB.prepare(
            `SELECT i.*, m.title, m.release_year,
                    COALESCE(SUM(CASE WHEN v.verdict = 'approve' THEN v.weight ELSE 0 END), 0) AS approve_weight,
                    COALESCE(SUM(CASE WHEN v.verdict = 'reject'  THEN v.weight ELSE 0 END), 0) AS reject_weight,
                    (SELECT COUNT(*) FROM image_reports r WHERE r.image_id = i.id) AS report_count
             FROM media_images i
             JOIN media_items m ON m.key = i.media_key
             LEFT JOIN image_votes v ON v.image_id = i.id
             WHERE i.moderator_status IS NOT NULL
             GROUP BY i.id
             HAVING i.report_weight > 0 OR reject_weight > 0
             ORDER BY i.report_weight DESC, reject_weight DESC
             LIMIT ?`
        ).bind(limit).all();

        return json({
            items: rows.results.map((row) => ({
                ...serializeImage(row),
                title: row.title,
                releaseYear: row.release_year,
                reportCount: row.report_count,
                // What the community would have decided without the lock.
                shadowApproveWeight: row.approve_weight,
                shadowRejectWeight: row.reject_weight
            }))
        });
    }

    // PATCH /v1/curation/images/{id} — moderator tools: tier, rank, clustering, hash
    if (segments[0] === "images" && segments.length === 2 && request.method === "PATCH") {
        const user = await authenticate(request, env);
        const body = await readJSON(request);

        const imageId = Number.parseInt(segments[1], 10);
        if (!Number.isInteger(imageId)) throw badRequest("Image id must be an integer");

        const image = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
        if (!image) throw notFound("Unknown image");

        // The perceptual hash is computed on device when a frame is first seen,
        // so any signed-in client may write it. Everything else here is a
        // curator judgement and needs the role.
        const wantsModeratorFields =
            body.difficultyTier !== undefined ||
            body.difficultyRank !== undefined ||
            body.clusteredWith !== undefined ||
            body.status !== undefined;
        if (wantsModeratorFields) requireRole(user, "moderator");

        if (body.perceptualHash !== undefined) {
            await env.DB.prepare("UPDATE media_images SET perceptual_hash = ? WHERE id = ?")
                .bind(body.perceptualHash === null ? null : String(body.perceptualHash).slice(0, 64), imageId)
                .run();
        }

        if (body.difficultyTier !== undefined) {
            if (body.difficultyTier !== null && !DIFFICULTY_TIERS.includes(body.difficultyTier)) {
                throw badRequest(`difficultyTier must be null or one of: ${DIFFICULTY_TIERS.join(", ")}`);
            }
            await env.DB.prepare("UPDATE media_images SET difficulty_tier = ? WHERE id = ?")
                .bind(body.difficultyTier, imageId)
                .run();
        }

        if (body.difficultyRank !== undefined) {
            const rank = body.difficultyRank === null ? null : Number.parseInt(body.difficultyRank, 10);
            if (rank !== null && (!Number.isInteger(rank) || rank < 1 || rank > 6)) {
                throw badRequest("difficultyRank must be null or 1–6");
            }
            // Ranks are exact positions, so claiming one silently releases
            // whoever held it. Last write wins, no blocking validation.
            if (rank !== null) {
                await env.DB.prepare(
                    "UPDATE media_images SET difficulty_rank = NULL WHERE media_key = ? AND difficulty_rank = ? AND id != ?"
                ).bind(image.media_key, rank, imageId).run();
            }
            await env.DB.prepare("UPDATE media_images SET difficulty_rank = ? WHERE id = ?").bind(rank, imageId).run();
        }

        if (body.clusteredWith !== undefined) {
            await env.DB.prepare("UPDATE media_images SET clustered_with = ? WHERE id = ?")
                .bind(body.clusteredWith === null ? null : String(body.clusteredWith).slice(0, 200), imageId)
                .run();
        }

        if (body.status !== undefined) {
            if (!IMAGE_STATUSES.includes(body.status)) throw badRequest("Unknown image status");
            await env.DB.prepare("UPDATE media_images SET status = ? WHERE id = ?").bind(body.status, imageId).run();
            await refreshMediaCounters(env, image.media_key);
        }

        const refreshed = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
        return json(serializeImage(refreshed));
    }

    // GET /v1/curation/reports — the moderator's report feed
    if (segments[0] === "reports" && request.method === "GET") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 50, min: 1, max: 200 });

        const rows = await env.DB.prepare(
            `SELECT r.image_id, r.reason, r.weight, r.created_at,
                    i.file_path, i.status, i.report_weight, i.media_key, m.title
             FROM image_reports r
             JOIN media_images i ON i.id = r.image_id
             JOIN media_items m ON m.key = i.media_key
             ORDER BY r.created_at DESC
             LIMIT ?`
        ).bind(limit).all();

        return json({
            reports: rows.results.map((row) => ({
                imageId: row.image_id,
                mediaKey: row.media_key,
                title: row.title,
                filePath: row.file_path,
                reason: row.reason,
                weight: row.weight,
                imageStatus: row.status,
                totalReportWeight: row.report_weight,
                createdAt: row.created_at
            }))
        });
    }

    return null;
}
