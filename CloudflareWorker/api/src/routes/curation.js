// Curation of frames.
//
// Only a moderator makes a frame playable, directly or by applying a curator's
// batch. Players have one voice: the in-round report, and enough live report
// weight hides a frame no moderator has locked.

import {
    badRequest,
    conflict,
    forbidden,
    json,
    noContent,
    notFound,
    optionalString,
    parseInteger,
    readJSON,
    requireEnum,
    requireString
} from "../lib/http.js";
import { authenticate, requireRole, roleRank } from "../lib/auth.js";
import {
    acquireLease,
    canTakeOver,
    isLive,
    loadLease,
    releaseLease,
    serializeLease,
    takeNotices,
    takeOverLease,
    touchLease
} from "../lib/leases.js";
import {
    DIFFICULTY_TIERS,
    IMAGE_STATUSES,
    MEDIA_TYPES,
    REPORT_REASONS,
    loadGenreIds,
    refreshMediaCounters,
    serializeImage,
    serializeMediaItem
} from "../lib/media.js";
import { readConfig } from "../lib/config.js";
import { limitByUser, reporterWeight } from "../lib/limits.js";
import { applyVerdicts, parseVerdicts } from "../lib/verdicts.js";

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
    // Once for the whole surface: every route below needs an account, and the
    // switch underneath runs before any of them.
    const user = await authenticate(request, env);
    const config = await readConfig(env);
    const windowMs = Math.max(1, config.curationLeaseMinutes) * 60 * 1000;

    // Moderators keep working while it is off: freezing the review queue too
    // would strand every batch already in flight.
    if (!config.curationEnabled && roleRank(user.role) < roleRank("moderator")) {
        throw forbidden("Curation is paused right now");
    }

    // ---------------------------------------------------------------- leases
    // Dealt from the queue, searched for, or opened to review a batch: one lock.
    if (segments[0] === "leases") {
        const now = Date.now();

        if (segments.length === 1 && request.method === "GET") {
            const notices = await takeNotices(env, user.uid, { now });

            // A curator has no business knowing who else is working; a
            // moderator deciding whether to take a title over does.
            const rows = user.role === "user"
                ? await env.DB.prepare(
                    `SELECT l.*, u.display_name FROM title_leases l LEFT JOIN users u ON u.uid = l.uid
                     WHERE l.uid = ? AND l.released_at IS NULL AND l.touched_at > ?`
                ).bind(user.uid, now - windowMs).all()
                : await env.DB.prepare(
                    `SELECT l.*, u.display_name FROM title_leases l LEFT JOIN users u ON u.uid = l.uid
                     WHERE l.released_at IS NULL AND l.touched_at > ? ORDER BY l.touched_at DESC LIMIT 100`
                ).bind(now - windowMs).all();

            return json({
                leases: rows.results.map((row) => serializeLease(row, { now, windowMs, uid: user.uid })),
                notices,
                heartbeatSeconds: config.curationHeartbeatSeconds,
                leaseMinutes: config.curationLeaseMinutes
            });
        }

        const mediaKey = segments[1];
        if (!mediaKey) throw badRequest("A media key is required");

        if (segments.length === 2 && request.method === "POST") {
            const item = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(mediaKey).first();
            if (!item) throw notFound(`Unknown media item "${mediaKey}"`);

            const body = await readJSON(request).catch(() => ({}));
            const notices = await takeNotices(env, user.uid, { now });

            let lease = await acquireLease(env, user, mediaKey, { now, windowMs });

            if (!lease) {
                const holder = await loadLease(env, mediaKey);

                if (body.takeover === true && holder && canTakeOver(user, holder)) {
                    lease = await takeOverLease(env, user, holder, mediaKey, { reason: body.reason, now });
                }

                if (!lease) {
                    return json(
                        {
                            error: "lease_held",
                            message: "Someone else is working on this title",
                            lease: serializeLease(holder, { now, windowMs, uid: user.uid }),
                            canTakeOver: Boolean(holder && canTakeOver(user, holder)),
                            notices
                        },
                        409
                    );
                }
            }

            const pending = await env.DB.prepare(
                "SELECT id FROM curation_batches WHERE media_key = ? AND state = 'pending'"
            ).bind(mediaKey).first();

            return json({
                lease: serializeLease({ ...lease, display_name: user.display_name }, { now, windowMs, uid: user.uid }),
                heartbeatSeconds: config.curationHeartbeatSeconds,
                // A title with a batch waiting has one way in: reviewing it.
                pendingBatchId: pending?.id ?? null,
                notices
            });
        }

        // Carries nothing on purpose: "someone is still here" is all the expiry
        // rule needs, and the draft never leaves the device.
        if (segments[2] === "heartbeat" && request.method === "POST") {
            const lease = await touchLease(env, user, mediaKey, { now, windowMs });
            if (!lease) {
                const holder = await loadLease(env, mediaKey);
                return json(
                    {
                        error: "lease_lost",
                        message: "This title is no longer leased to you",
                        lease: isLive(holder, { now, windowMs })
                            ? serializeLease(holder, { now, windowMs, uid: user.uid })
                            : null,
                        notices: await takeNotices(env, user.uid, { now })
                    },
                    409
                );
            }

            return json({ lease: serializeLease(lease, { now, windowMs, uid: user.uid }) });
        }

        if (segments.length === 2 && request.method === "DELETE") {
            await releaseLease(env, user, mediaKey, { now });
            return noContent();
        }
    }

    // ------------------------------------------------------------ work queue
    // The frame queue's weight, lifted onto titles. Curators are dealt work
    // rather than searching for it, which is what makes coverage systematic.
    if (segments[0] === "queue" && segments[1] === "titles" && request.method === "GET") {
        const mediaType = url.searchParams.get("mediaType");
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");
        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 20, min: 1, max: 100 });

        const rows = await queueTitles(env, {
            uid: user.uid,
            mediaType,
            limit,
            target: config.targetApprovedFrames,
            windowMs: Math.max(1, config.curationLeaseMinutes) * 60 * 1000
        });

        return json({
            items: rows.map(serializeQueueRow),
            targetApprovedFrames: config.targetApprovedFrames
        });
    }

    // POST /v1/curation/queue/claim — hand out the next title and lease it
    if (segments[0] === "queue" && segments[1] === "claim" && request.method === "POST") {
        const now = Date.now();

        const body = await readJSON(request).catch(() => ({}));
        const mediaType = body.mediaType ?? null;
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");

        // Someone who already holds a title gets that title back rather than a
        // second one: the draft for it is still sitting on their device.
        const held = await env.DB.prepare(
            `SELECT media_key FROM title_leases
             WHERE uid = ? AND released_at IS NULL AND touched_at > ? ORDER BY touched_at DESC LIMIT 1`
        ).bind(user.uid, now - windowMs).first();

        const candidates = held
            ? [{ key: held.media_key }]
            : await queueTitles(env, {
                uid: user.uid,
                mediaType,
                limit: 5,
                target: config.targetApprovedFrames,
                windowMs
            });

        // Walking a few candidates rather than one: between the read and the
        // write someone else may have taken the top title.
        for (const candidate of candidates) {
            const lease = await acquireLease(env, user, candidate.key, { now, windowMs });
            if (!lease) continue;

            const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(candidate.key).first();
            const genres = await loadGenreIds(env, [candidate.key]);

            return json({
                item: serializeMediaItem(item, genres.get(candidate.key) || []),
                lease: serializeLease(lease, { now, windowMs, uid: user.uid }),
                heartbeatSeconds: config.curationHeartbeatSeconds,
                resumed: Boolean(held)
            });
        }

        return json(
            {
                error: "queue_empty",
                message: "Nothing in the catalogue needs curating right now"
            },
            404
        );
    }

    // --------------------------------------------------------------- batches
    // A proposal for one title, never applied by itself.
    if (segments[0] === "batches") {
        const now = Date.now();

        // POST /v1/curation/batches — submit one
        if (segments.length === 1 && request.method === "POST") {
            const body = await readJSON(request);
            const batchId = requireString(body, "batchId", { maxLength: 64 });
            const mediaKey = requireString(body, "mediaKey", { maxLength: 60 });

            // The id is the client's idempotency key. This lookup comes first
            // because submitting releases the lease, so a retry would fail the
            // lease check below.
            const existing = await loadBatch(env, batchId);
            if (existing) {
                if (existing.uid !== user.uid) throw conflict("That batch id belongs to someone else");
                return json({ batch: serializeBatch(existing), duplicate: true });
            }

            const item = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(mediaKey).first();
            if (!item) throw notFound(`Unknown media item "${mediaKey}"`);

            await limitByUser(env, user.uid, "WRITE_LIMITER");

            // The one server-side rule the whole draft model rests on. Without
            // it a batch could be built on a state that has since moved on.
            const lease = await touchLease(env, user, mediaKey, { now, windowMs });
            if (!lease) {
                const holder = await loadLease(env, mediaKey);
                return json(
                    {
                        error: "lease_lost",
                        message: "Your lease on this title has expired or been taken over",
                        lease: isLive(holder, { now, windowMs })
                            ? serializeLease(holder, { now, windowMs, uid: user.uid })
                            : null,
                        notices: await takeNotices(env, user.uid, { now })
                    },
                    409
                );
            }

            const open = await env.DB.prepare(
                "SELECT id FROM curation_batches WHERE media_key = ? AND state = 'pending'"
            ).bind(mediaKey).first();
            if (open) throw conflict(`This title already has a batch awaiting review (${open.id})`);

            const verdicts = parseVerdicts(body.verdicts);
            if (!verdicts.length) throw badRequest("A batch needs at least one verdict");

            await env.DB.prepare(
                `INSERT INTO curation_batches (id, media_key, uid, state, verdicts, reject_remaining, note, submitted_at)
                 VALUES (?, ?, ?, 'pending', ?, ?, ?, ?)`
            ).bind(
                batchId,
                mediaKey,
                user.uid,
                JSON.stringify(verdicts),
                body.rejectRemaining === true ? 1 : 0,
                optionalString(body, "note", { maxLength: 500 }),
                now
            ).run();

            // The title is held out of the queue by the pending batch from here
            // on, so the lease has nothing left to do.
            await releaseLease(env, user, mediaKey, { now });

            return json({ batch: serializeBatch(await loadBatch(env, batchId)) });
        }

        // GET /v1/curation/batches — the review queue, or "my submissions"
        if (segments.length === 1 && request.method === "GET") {
            const state = url.searchParams.get("state");
            if (state && !["pending", "applied", "rejected"].includes(state)) throw badRequest("Unknown batch state");
            const limit = parseInteger(url.searchParams.get("limit"), { fallback: 50, min: 1, max: 200 });

            const mine = user.role === "user" || url.searchParams.get("scope") === "mine";

            const rows = await env.DB.prepare(
                `SELECT b.*, m.title, m.poster_url, m.approved_images, u.display_name
                 FROM curation_batches b
                 JOIN media_items m ON m.key = b.media_key
                 LEFT JOIN users u ON u.uid = b.uid
                 WHERE (?1 IS NULL OR b.state = ?1) AND (?2 = 0 OR b.uid = ?3)
                 ORDER BY b.submitted_at DESC LIMIT ?4`
            ).bind(state || null, mine ? 1 : 0, user.uid, limit).all();

            return json({ batches: rows.results.map(serializeBatch) });
        }

        const batchId = segments[1];
        const batch = batchId ? await loadBatch(env, batchId) : null;
        if (!batch) throw notFound("Unknown batch");

        // GET /v1/curation/batches/{id} — the proposal against the title as it stands now
        if (segments.length === 2 && request.method === "GET") {
            if (batch.uid !== user.uid) requireRole(user, "moderator");

            const images = await env.DB.prepare(
                "SELECT * FROM media_images WHERE media_key = ? ORDER BY tmdb_vote_average ASC"
            ).bind(batch.media_key).all();

            const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(batch.media_key).first();
            const genres = await loadGenreIds(env, [batch.media_key]);
            const diff = diffBatch(batch, images.results);

            return json({
                batch: serializeBatch(batch),
                item: serializeMediaItem(item, genres.get(batch.media_key) || []),
                frames: diff.frames,
                consequences: diff.consequences,
                targetApprovedFrames: config.targetApprovedFrames
            });
        }

        // POST /v1/curation/batches/{id}/apply — accept it, with or without edits
        if (segments[2] === "apply" && request.method === "POST") {
            requireRole(user, "moderator");
            if (batch.state !== "pending") throw conflict(`This batch is already ${batch.state}`);

            const lease = await holdForReview(env, user, batch.media_key, { now, windowMs });
            if (lease.error) return json(lease.error, 409);

            const body = await readJSON(request).catch(() => ({}));
            const final = body.verdicts === undefined ? JSON.parse(batch.verdicts) : parseVerdicts(body.verdicts);
            const rejectRemaining = body.rejectRemaining === undefined
                ? batch.reject_remaining === 1
                : body.rejectRemaining === true;

            const { editsCount, overturnedApprovals } = compareVerdicts(JSON.parse(batch.verdicts), final);

            await applyVerdicts(env, {
                mediaKey: batch.media_key,
                verdicts: final,
                rejectRemaining,
                moderatorUid: user.uid,
                now
            });

            await env.DB.prepare(
                `UPDATE curation_batches
                 SET state = 'applied', review_outcome = 'applied', reviewed_by = ?, reviewed_at = ?,
                     review_note = ?, edits_count = ?, overturned_approvals = ?
                 WHERE id = ?`
            ).bind(user.uid, now, optionalString(body, "note", { maxLength: 500 }), editsCount, overturnedApprovals, batch.id).run();

            await releaseLease(env, user, batch.media_key, { now });

            const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(batch.media_key).first();
            const genres = await loadGenreIds(env, [batch.media_key]);

            return json({
                batch: serializeBatch(await loadBatch(env, batch.id)),
                item: serializeMediaItem(item, genres.get(batch.media_key) || []),
                applied: final.length,
                editsCount,
                overturnedApprovals
            });
        }

        // POST /v1/curation/batches/{id}/reject — neutral, or as poor work
        if (segments[2] === "reject" && request.method === "POST") {
            requireRole(user, "moderator");
            if (batch.state !== "pending") throw conflict(`This batch is already ${batch.state}`);

            const body = await readJSON(request);
            // "The title is not wanted" must not count against the person who
            // curated it — that is a decision about the film, not their work.
            const outcome = requireEnum(body, "outcome", ["neutral", "poor"]);

            await env.DB.prepare(
                `UPDATE curation_batches
                 SET state = 'rejected', review_outcome = ?, reviewed_by = ?, reviewed_at = ?, review_note = ?
                 WHERE id = ?`
            ).bind(`rejected_${outcome}`, user.uid, now, optionalString(body, "note", { maxLength: 500 }), batch.id).run();

            return json({ batch: serializeBatch(await loadBatch(env, batch.id)) });
        }
    }

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
                  WHERE media_key = ? AND status = 'approved' AND id != ?
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

    // POST /v1/curation/images/{id}/lock — a verdict reports cannot overturn
    if (segments[0] === "images" && segments[2] === "lock" && request.method === "POST") {
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

    // GET /v1/curation/contested — locked frames players keep reporting
    if (segments[0] === "contested" && request.method === "GET") {
        requireRole(user, "moderator");

        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 50, min: 1, max: 200 });

        const rows = await env.DB.prepare(
            `SELECT i.*, m.title, m.release_year,
                    (SELECT COUNT(*) FROM image_reports r
                      WHERE r.image_id = i.id AND r.dismissed_at IS NULL) AS report_count
             FROM media_images i
             JOIN media_items m ON m.key = i.media_key
             -- report_weight counts live reports only: a dismissed complaint is
             -- settled, and counting it would pin a cleared frame here forever.
             WHERE i.moderator_status IS NOT NULL AND i.report_weight > 0
             ORDER BY i.report_weight DESC
             LIMIT ?`
        ).bind(limit).all();

        return json({
            items: rows.results.map((row) => ({
                ...serializeImage(row),
                title: row.title,
                releaseYear: row.release_year,
                reportCount: row.report_count
            }))
        });
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
        requireRole(user, "moderator");

        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 50, min: 1, max: 200 });
        // Off by default because the feed is a work queue; on demand because
        // judging a serial reporter means reading the ones already thrown out.
        const includeDismissed = url.searchParams.get("includeDismissed") === "true";

        const rows = await env.DB.prepare(
            `SELECT r.image_id, r.reason, r.weight, r.created_at, r.uid, r.dismissed_at,
                    i.file_path, i.status, i.report_weight, i.media_key, m.title
             FROM image_reports r
             JOIN media_images i ON i.id = r.image_id
             JOIN media_items m ON m.key = i.media_key
             WHERE (?1 = 1 OR r.dismissed_at IS NULL)
             ORDER BY r.created_at DESC
             LIMIT ?2`
        ).bind(includeDismissed ? 1 : 0, limit).all();

        return json({
            reports: rows.results.map((row) => ({
                imageId: row.image_id,
                mediaKey: row.media_key,
                title: row.title,
                filePath: row.file_path,
                reason: row.reason,
                weight: row.weight,
                reportedBy: row.uid,
                dismissedAt: row.dismissed_at ?? null,
                imageStatus: row.status,
                totalReportWeight: row.report_weight,
                createdAt: row.created_at
            }))
        });
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

// The queue read, shared by browsing it and by being dealt the next title.
async function queueTitles(env, { uid, mediaType, limit, target, windowMs }) {
    const rows = await env.DB.prepare(
        `SELECT m.*,
                m.popularity * (CAST(?1 - m.approved_images AS REAL) / ?1) + 0.01 AS weight,
                (SELECT COUNT(*) FROM media_images i
                  WHERE i.media_key = m.key AND i.status = 'pending') AS pending_images,
                (SELECT COUNT(*) FROM media_images i
                  WHERE i.media_key = m.key AND i.moderator_status IS NULL) AS unjudged_images
         FROM media_items m
         WHERE (?2 IS NULL OR m.media_type = ?2)
           AND m.status != 'rejected'
           AND m.admin_finalized = 0
           AND m.total_images > 0
           AND m.approved_images < ?1
           AND m.reviewed_images < m.total_images
           AND NOT EXISTS (
               SELECT 1 FROM title_leases l
               WHERE l.media_key = m.key AND l.released_at IS NULL AND l.touched_at > ?3 AND l.uid != ?4
           )
           AND NOT EXISTS (
               SELECT 1 FROM curation_batches b WHERE b.media_key = m.key AND b.state = 'pending'
           )
         ORDER BY weight DESC, m.key
         LIMIT ?5`
    ).bind(target, mediaType || null, Date.now() - windowMs, uid, limit).all();

    return rows.results;
}

function serializeQueueRow(row) {
    return {
        ...serializeMediaItem(row),
        weight: row.weight,
        pendingImages: row.pending_images,
        unjudgedImages: row.unjudged_images
    };
}

async function loadBatch(env, batchId) {
    return env.DB.prepare(
        `SELECT b.*, m.title, m.poster_url, m.approved_images, u.display_name
         FROM curation_batches b
         JOIN media_items m ON m.key = b.media_key
         LEFT JOIN users u ON u.uid = b.uid
         WHERE b.id = ?`
    ).bind(batchId).first();
}

function serializeBatch(row) {
    const verdicts = JSON.parse(row.verdicts);
    return {
        id: row.id,
        mediaKey: row.media_key,
        title: row.title,
        posterURL: row.poster_url ?? null,
        uid: row.uid,
        displayName: row.display_name ?? null,
        state: row.state,
        proposedApprovals: verdicts.filter((verdict) => verdict.status === "approved").length,
        proposedRejections: verdicts.filter((verdict) => verdict.status === "rejected").length,
        rejectRemaining: row.reject_remaining === 1,
        note: row.note,
        submittedAt: row.submitted_at,
        reviewedBy: row.reviewed_by,
        reviewedAt: row.reviewed_at,
        reviewOutcome: row.review_outcome,
        reviewNote: row.review_note,
        editsCount: row.edits_count,
        overturnedApprovals: row.overturned_approvals
    };
}

// The proposal laid over the title as it stands now, plus what applying it
// would do to the playable pool.
function diffBatch(batch, images) {
    const proposed = new Map(JSON.parse(batch.verdicts).map((verdict) => [verdict.imageId, verdict]));
    const rejectRemaining = batch.reject_remaining === 1;

    const frames = images.map((image) => {
        const verdict = proposed.get(image.id);
        const proposedStatus = verdict
            ? verdict.status
            : rejectRemaining && image.moderator_status === null
                ? "rejected"
                : null;

        return {
            ...serializeImage(image),
            proposedStatus,
            proposedTier: verdict?.difficultyTier ?? null,
            // Re-importing only ever adds rows, so an unjudged frame is a new one.
            isNew: image.moderator_status === null,
            changesStatus: proposedStatus !== null && proposedStatus !== image.status
        };
    });

    const approvedNow = images.filter((image) => image.status === "approved").length;
    const approvedAfter = frames.filter(
        (frame) => (frame.proposedStatus ?? frame.status) === "approved"
    ).length;

    const warnings = [];
    if (approvedAfter < 6) warnings.push("below_playable");
    else if (approvedAfter <= 6) warnings.push("no_spares");

    return {
        frames,
        consequences: { approvedNow, approvedAfter, playableThreshold: 6, spareFramesAfter: Math.max(0, approvedAfter - 6), warnings }
    };
}

// Picking a different good frame is not a mistake; having picks thrown out is.
function compareVerdicts(proposal, final) {
    const finalById = new Map(final.map((verdict) => [verdict.imageId, verdict.status]));
    const proposalById = new Map(proposal.map((verdict) => [verdict.imageId, verdict.status]));

    let editsCount = 0;
    let overturnedApprovals = 0;

    for (const [imageId, status] of proposalById) {
        const settled = finalById.get(imageId) ?? null;
        if (settled !== status) editsCount += 1;
        if (status === "approved" && settled !== "approved") overturnedApprovals += 1;
    }
    for (const imageId of finalById.keys()) {
        if (!proposalById.has(imageId)) editsCount += 1;
    }

    return { editsCount, overturnedApprovals };
}

// Reviewing takes the same lease as curating: a free title is picked up
// silently, one held by someone else stops the review.
async function holdForReview(env, user, mediaKey, { now, windowMs }) {
    const lease = await acquireLease(env, user, mediaKey, { now, windowMs });
    if (lease) return { lease };

    const holder = await loadLease(env, mediaKey);
    return {
        error: {
            error: "lease_held",
            message: "Someone else is working on this title",
            lease: serializeLease(holder, { now, windowMs, uid: user.uid }),
            canTakeOver: Boolean(holder && canTakeOver(user, holder))
        }
    };
}
