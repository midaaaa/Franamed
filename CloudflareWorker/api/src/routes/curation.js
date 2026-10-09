// Curation of frames.
//
// Only a moderator makes a frame playable. Players have one voice: the in-round
// report, and enough live report weight hides a frame no moderator has judged.

import { badRequest, json, notFound, readJSON, requireEnum } from "../lib/http.js";
import { authenticate, requireRole } from "../lib/auth.js";
import {
    DIFFICULTY_TIERS,
    IMAGE_STATUSES,
    REPORT_REASONS,
    refreshMediaCounters,
    serializeImage
} from "../lib/media.js";
import { readConfig } from "../lib/config.js";
import { limitByUser, reporterWeight } from "../lib/limits.js";
import { handleCurationScreens } from "./curationScreens.js";

// Recomputes one image's status from the reports on it, then updates
// its title's cached counters. Everything that can change an image's standing
// funnels through here so the derivation lives in exactly one place.
async function recomputeImageStatus(env, imageId) {
    const config = await readConfig(env);

    const image = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
    if (!image) throw notFound("Unknown image");

    // Dismissed rows are kept as evidence but stop counting.
    const reports = await env.DB.prepare(
        "SELECT COALESCE(SUM(weight), 0) AS weight FROM image_reports WHERE image_id = ? AND dismissed_at IS NULL"
    ).bind(imageId).first();

    // A moderator verdict is final. Reports still land — they are how a
    // moderator finds out they were wrong — they just stop deciding.
    let status;
    if (image.moderator_status) {
        status = image.moderator_status;
    } else if (reports.weight >= config.autoHideReportWeight) {
        status = "rejected";
    } else {
        status = "pending";
    }

    await env.DB.prepare("UPDATE media_images SET status = ?, report_weight = ? WHERE id = ?")
        .bind(status, reports.weight, imageId)
        .run();

    await refreshMediaCounters(env, image.media_key);
    return { ...image, status, report_weight: reports.weight };
}

export async function handleCuration(request, env, segments, url) {
    const user = await authenticate(request, env);
    const config = await readConfig(env);

    const screen = await handleCurationScreens(request, env, segments, url, { user, config });
    if (screen) return screen;

    // POST /v1/curation/report — the in-round "something is wrong with this frame" button
    if (segments[0] === "report" && request.method === "POST") {
        const body = await readJSON(request);

        const imageId = Number.parseInt(body.imageId, 10);
        if (!Number.isInteger(imageId)) throw badRequest("imageId must be an integer");
        const reason = requireEnum(body, "reason", REPORT_REASONS);

        const image = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
        if (!image) throw notFound("Unknown image");

        await limitByUser(env, user.uid, "WRITE_LIMITER");
        const reportWeight = await reporterWeight(env, user);
        const now = Date.now();

        await env.DB.prepare(
            `INSERT INTO image_reports (image_id, uid, reason, weight, created_at)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT (image_id, uid) DO UPDATE SET
                reason = excluded.reason,
                weight = excluded.weight,
                created_at = excluded.created_at,
                dismissed_at = NULL,
                dismissed_by = NULL`
        ).bind(imageId, user.uid, reason, reportWeight, now).run();

        const updated = await recomputeImageStatus(env, imageId);

        // A replacement is offered for the one-frame mode, where the reported
        // image is the whole round, and no attempt is charged: the player is
        // compensating for broken content, not failing to recognise a film.
        //
        // Two limits keep that from being a free swap for any hard frame: the
        // replacement is never easier, and someone who keeps reporting the
        // same title stops being handed new frames.
        const reportsToday = await env.DB.prepare(
            `SELECT COUNT(*) AS count
               FROM image_reports r JOIN media_images i ON i.id = r.image_id
              WHERE r.uid = ? AND i.media_key = ? AND r.dismissed_at IS NULL AND r.created_at > ?`
        ).bind(user.uid, image.media_key, now - 24 * 60 * 60 * 1000).first();

        let replacement = null;
        if (reportsToday.count <= config.reportReplacementLimit) {
            const candidates = await env.DB.prepare(
                `SELECT * FROM media_images
                  WHERE media_key = ? AND status = 'approved' AND missing_at IS NULL AND id != ?
                  ORDER BY RANDOM() LIMIT 20`
            ).bind(image.media_key, imageId).all();

            replacement = pickReplacement(candidates.results, image.difficulty_tier);
        }

        return json({
            image: serializeImage(updated),
            replacement: replacement ? serializeImage(replacement) : null,
            replacementsRemaining: Math.max(0, config.reportReplacementLimit - reportsToday.count + 1)
        });
    }

    // POST /v1/curation/images/{id}/dismiss-disputes — "the complaints are wrong"
    if (segments[0] === "images" && segments[2] === "dismiss-disputes" && request.method === "POST") {
        requireRole(user, "moderator");

        const imageId = Number.parseInt(segments[1], 10);
        if (!Number.isInteger(imageId)) throw badRequest("Image id must be an integer");

        // Marked, never deleted: these rows are the evidence for judging the
        // people who filed them. A dismissed row stops counting towards the
        // frame's status and stays readable. The frame's own dismissal count
        // is separate, so one cleared three times still reads as one that
        // keeps attracting complaints.
        const dismissedAt = Date.now();
        await env.DB.batch([
            env.DB.prepare(
                "UPDATE image_reports SET dismissed_at = ?, dismissed_by = ? WHERE image_id = ? AND dismissed_at IS NULL"
            ).bind(dismissedAt, user.uid, imageId),
            env.DB.prepare(
                `UPDATE media_images
                 SET disputes_dismissed_at = ?, disputes_dismissed_count = disputes_dismissed_count + 1
                 WHERE id = ?`
            ).bind(dismissedAt, imageId)
        ]);

        return json(serializeImage(await recomputeImageStatus(env, imageId)));
    }

    // POST /v1/curation/images/{id}/restore — a missing frame is fine after all;
    // POST /v1/curation/images/{id}/remove — it is gone for good: rejected and
    // locked, the row kept so a re-import does not bring it back as new
    if (segments[0] === "images" && ["restore", "remove"].includes(segments[2]) && request.method === "POST") {
        requireRole(user, "moderator");

        const imageId = Number.parseInt(segments[1], 10);
        if (!Number.isInteger(imageId)) throw badRequest("Image id must be an integer");
        const image = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
        if (!image) throw notFound("Unknown image");

        const now = Date.now();
        await (segments[2] === "restore"
            ? env.DB.prepare("UPDATE media_images SET missing_at = NULL WHERE id = ? AND removed_at IS NULL").bind(imageId)
            : env.DB.prepare(
                `UPDATE media_images
                 SET removed_at = ?1, status = 'rejected', moderator_status = 'rejected', moderator_uid = ?2, moderator_at = ?1
                 WHERE id = ?3`
            ).bind(now, user.uid, imageId)
        ).run();
        await refreshMediaCounters(env, image.media_key);

        const refreshed = await env.DB.prepare("SELECT * FROM media_images WHERE id = ?").bind(imageId).first();
        return json(serializeImage(refreshed));
    }

    // PATCH /v1/curation/images/{id} — moderator tools: tier, rank, clustering, hash
    if (segments[0] === "images" && segments.length === 2 && request.method === "PATCH") {
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
            if (body.difficultyTier !== null && image.moderator_status !== "approved") {
                throw badRequest("Only an approved frame takes a difficultyTier");
            }
            await env.DB.prepare("UPDATE media_images SET difficulty_tier = ? WHERE id = ?")
                .bind(body.difficultyTier, imageId)
                .run();
            if (body.status === undefined) await refreshMediaCounters(env, image.media_key);
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

    return null;
}

// A stand-in for a reported frame, never an easier one. Candidates arrive in
// random order, so the first allowed one is a random pick among them. With
// nothing at or above the reported difficulty the hardest left is handed over
// rather than nothing — a broken frame still has to be replaced. Untagged
// counts as easiest: it is the one nobody has vouched for.
function pickReplacement(candidates, reportedTier) {
    if (!candidates.length) return null;

    const rank = (row) => {
        const index = DIFFICULTY_TIERS.indexOf(row.difficulty_tier);
        return index === -1 ? DIFFICULTY_TIERS.length : index;
    };

    const bar = DIFFICULTY_TIERS.indexOf(reportedTier);
    if (bar === -1) return candidates[0];

    const notEasier = candidates.filter((row) => rank(row) <= bar);
    if (notEasier.length) return notEasier[0];

    return [...candidates].sort((a, b) => rank(a) - rank(b))[0];
}
