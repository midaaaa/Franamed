// Curated collections and a player's progress through them.
//
// Progress is reported as two separate numbers — how much of the list has been
// played, and how much of what was played was right. Folding those into one
// fraction produces a figure nobody can interpret.

import { badRequest, json, notFound, readJSON, requireEnum, requireString, optionalString } from "../lib/http.js";
import { authenticate, requireRole } from "../lib/auth.js";
import { MEDIA_TYPES } from "../lib/media.js";
import { readConfig } from "../lib/config.js";
import { grantBonusAttempts } from "../lib/daily.js";

// Progress rows are matched against the playlist's *current* contents rather
// than pruned when a curator edits the list. A title removed and later put back
// keeps the progress it had, and nothing has to be cleaned up on edit.
async function progressSummary(env, uid, playlistId) {
    const row = await env.DB.prepare(
        `SELECT
            (SELECT COUNT(*) FROM playlist_items WHERE playlist_id = ?) AS total,
            (SELECT COUNT(*) FROM playlist_progress pr
              JOIN playlist_items pi ON pi.playlist_id = pr.playlist_id AND pi.media_key = pr.media_key
              WHERE pr.uid = ? AND pr.playlist_id = ? AND pr.state = 'completed') AS answered,
            (SELECT COUNT(*) FROM playlist_progress pr
              JOIN playlist_items pi ON pi.playlist_id = pr.playlist_id AND pi.media_key = pr.media_key
              WHERE pr.uid = ? AND pr.playlist_id = ? AND pr.state = 'completed' AND pr.was_correct = 1) AS correct`
    ).bind(playlistId, uid, playlistId, uid, playlistId).first();

    const completion = await env.DB.prepare(
        "SELECT times_completed, completed_at FROM playlist_completions WHERE uid = ? AND playlist_id = ?"
    ).bind(uid, playlistId).first();

    return {
        total: row.total,
        answered: row.answered,
        correct: row.correct,
        accuracy: row.answered > 0 ? row.correct / row.answered : null,
        timesCompleted: completion?.times_completed ?? 0,
        completedAt: completion?.completed_at ?? null
    };
}

function serializePlaylist(row) {
    return {
        id: row.id,
        title: row.title,
        description: row.description,
        coverImageURL: row.cover_image_url,
        mediaType: row.media_type,
        source: row.source,
        allowUncurated: row.allow_uncurated === 1,
        published: row.published === 1,
        createdAt: row.created_at
    };
}

export async function handlePlaylists(request, env, segments, url) {
    // GET /v1/playlists
    if (segments.length === 0 && request.method === "GET") {
        const user = await authenticate(request, env);
        const mediaType = url.searchParams.get("mediaType");
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");

        const includeUnpublished = user.role !== "user" && url.searchParams.get("includeUnpublished") === "true";

        const rows = await env.DB.prepare(
            `SELECT * FROM playlists
             WHERE (? IS NULL OR media_type = ?) AND (published = 1 OR ?)
             ORDER BY created_at DESC`
        ).bind(mediaType || null, mediaType || null, includeUnpublished ? 1 : 0).all();

        const playlists = [];
        for (const row of rows.results) {
            playlists.push({ ...serializePlaylist(row), progress: await progressSummary(env, user.uid, row.id) });
        }
        return json({ playlists });
    }

    // POST /v1/playlists
    if (segments.length === 0 && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const body = await readJSON(request);
        const id = crypto.randomUUID();

        await env.DB.prepare(
            `INSERT INTO playlists (id, title, description, cover_image_url, media_type, source, allow_uncurated, created_by, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).bind(
            id,
            requireString(body, "title", { maxLength: 120 }),
            optionalString(body, "description", { maxLength: 1000 }),
            optionalString(body, "coverImageURL", { maxLength: 500 }),
            requireEnum(body, "mediaType", MEDIA_TYPES),
            body.source === "tmdb" ? "tmdb" : "curated",
            body.allowUncurated === true ? 1 : 0,
            user.uid,
            Date.now()
        ).run();

        const row = await env.DB.prepare("SELECT * FROM playlists WHERE id = ?").bind(id).first();
        return json(serializePlaylist(row), 201);
    }

    const playlistId = segments[0];
    if (!playlistId) return null;

    const playlist = await env.DB.prepare("SELECT * FROM playlists WHERE id = ?").bind(playlistId).first();
    if (!playlist) throw notFound("Unknown playlist");

    // GET /v1/playlists/{id}
    if (segments.length === 1 && request.method === "GET") {
        const user = await authenticate(request, env);

        const items = await env.DB.prepare(
            `SELECT m.key, m.title, m.release_year, m.poster_url, m.approved_images,
                    pr.state, pr.attempts_used, pr.was_correct
             FROM playlist_items pi
             JOIN media_items m ON m.key = pi.media_key
             LEFT JOIN playlist_progress pr
               ON pr.media_key = pi.media_key AND pr.playlist_id = pi.playlist_id AND pr.uid = ?
             WHERE pi.playlist_id = ?
             ORDER BY pi.position`
        ).bind(user.uid, playlistId).all();

        return json({
            ...serializePlaylist(playlist),
            progress: await progressSummary(env, user.uid, playlistId),
            items: items.results.map((row) => ({
                key: row.key,
                title: row.title,
                releaseYear: row.release_year,
                posterURL: row.poster_url,
                approvedImages: row.approved_images,
                state: row.state || "notStarted",
                attemptsUsed: row.attempts_used ?? 0,
                wasCorrect: row.was_correct === null || row.was_correct === undefined ? null : row.was_correct === 1
            }))
        });
    }

    // PATCH /v1/playlists/{id}
    if (segments.length === 1 && request.method === "PATCH") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");
        const body = await readJSON(request);

        // A collection is shown as a ticket, and a ticket needs something to
        // print on it. Publishing is refused unless the playlist has its own
        // cover or at least one member with a poster.
        if (body.published === true) {
            const hasArt = await env.DB.prepare(
                `SELECT 1 AS ok FROM playlist_items pi
                 JOIN media_items m ON m.key = pi.media_key
                 WHERE pi.playlist_id = ? AND m.poster_url IS NOT NULL LIMIT 1`
            ).bind(playlistId).first();

            if (!hasArt && !(body.coverImageURL || playlist.cover_image_url)) {
                throw badRequest("Publishing needs a cover image or at least one title with a poster");
            }
        }

        await env.DB.prepare(
            `UPDATE playlists SET
                title = COALESCE(?, title),
                description = COALESCE(?, description),
                cover_image_url = COALESCE(?, cover_image_url),
                allow_uncurated = COALESCE(?, allow_uncurated),
                published = COALESCE(?, published)
             WHERE id = ?`
        ).bind(
            optionalString(body, "title", { maxLength: 120 }),
            optionalString(body, "description", { maxLength: 1000 }),
            optionalString(body, "coverImageURL", { maxLength: 500 }),
            typeof body.allowUncurated === "boolean" ? (body.allowUncurated ? 1 : 0) : null,
            typeof body.published === "boolean" ? (body.published ? 1 : 0) : null,
            playlistId
        ).run();

        const row = await env.DB.prepare("SELECT * FROM playlists WHERE id = ?").bind(playlistId).first();
        return json(serializePlaylist(row));
    }

    // PUT /v1/playlists/{id}/items — replace the contents wholesale
    if (segments[1] === "items" && request.method === "PUT") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const body = await readJSON(request);
        const keys = Array.isArray(body.mediaKeys) ? body.mediaKeys.filter((key) => typeof key === "string") : [];

        const wrongType = keys.find((key) => !key.startsWith(`${playlist.media_type}_`));
        if (wrongType) throw badRequest(`"${wrongType}" is not a ${playlist.media_type}; playlists hold a single media type`);

        await env.DB.prepare("DELETE FROM playlist_items WHERE playlist_id = ?").bind(playlistId).run();

        if (keys.length) {
            await env.DB.batch(
                keys.map((key, index) =>
                    env.DB.prepare("INSERT INTO playlist_items (playlist_id, media_key, position) VALUES (?, ?, ?)")
                        .bind(playlistId, key, index)
                )
            );
        }

        return json({ id: playlistId, count: keys.length });
    }

    // POST /v1/playlists/{id}/progress — record one answered title
    if (segments[1] === "progress" && request.method === "POST") {
        const user = await authenticate(request, env);
        const body = await readJSON(request);

        const mediaKey = requireString(body, "mediaKey", { maxLength: 60 });
        const attemptsUsed = Number.parseInt(body.attemptsUsed, 10);
        if (!Number.isInteger(attemptsUsed) || attemptsUsed < 0 || attemptsUsed > 6) {
            throw badRequest("attemptsUsed must be 0–6");
        }
        if (typeof body.wasCorrect !== "boolean") throw badRequest("wasCorrect must be a boolean");

        // Retrying overwrites the single record for that title; no history is
        // kept, which is what makes "replay the ones I got wrong" simple.
        await env.DB.prepare(
            `INSERT INTO playlist_progress (uid, playlist_id, media_key, state, attempts_used, was_correct, updated_at)
             VALUES (?, ?, ?, 'completed', ?, ?, ?)
             ON CONFLICT (uid, playlist_id, media_key) DO UPDATE SET
                state = 'completed', attempts_used = excluded.attempts_used,
                was_correct = excluded.was_correct, updated_at = excluded.updated_at`
        ).bind(user.uid, playlistId, mediaKey, attemptsUsed, body.wasCorrect ? 1 : 0, Date.now()).run();

        const summary = await progressSummary(env, user.uid, playlistId);
        let awardedAttempts = 0;

        if (summary.total > 0 && summary.answered >= summary.total && summary.completedAt === null) {
            const config = await readConfig(env);
            await env.DB.prepare(
                `INSERT INTO playlist_completions (uid, playlist_id, times_completed, completed_at)
                 VALUES (?, ?, 1, ?)
                 ON CONFLICT (uid, playlist_id) DO UPDATE SET completed_at = excluded.completed_at`
            ).bind(user.uid, playlistId, Date.now()).run();

            awardedAttempts = config.playlistCompletionReward;
            await grantBonusAttempts(env, user.uid, awardedAttempts);
        }

        return json({ progress: await progressSummary(env, user.uid, playlistId), awardedAttempts });
    }

    // POST /v1/playlists/{id}/reset
    if (segments[1] === "reset" && request.method === "POST") {
        const user = await authenticate(request, env);
        const body = await readJSON(request);
        const mode = requireEnum(body, "mode", ["soft", "hard"]);

        if (mode === "soft") {
            // Only un-marks completion, so a curator adding titles to a
            // finished list does not wipe what the player already did.
            await env.DB.prepare("UPDATE playlist_completions SET completed_at = NULL WHERE uid = ? AND playlist_id = ?")
                .bind(user.uid, playlistId)
                .run();
        } else {
            await env.DB.batch([
                env.DB.prepare("DELETE FROM playlist_progress WHERE uid = ? AND playlist_id = ?").bind(user.uid, playlistId),
                env.DB.prepare(
                    `INSERT INTO playlist_completions (uid, playlist_id, times_completed, completed_at)
                     VALUES (?, ?, 1, NULL)
                     ON CONFLICT (uid, playlist_id) DO UPDATE SET
                        times_completed = playlist_completions.times_completed + 1, completed_at = NULL`
                ).bind(user.uid, playlistId)
            ]);
        }

        return json({ progress: await progressSummary(env, user.uid, playlistId) });
    }

    return null;
}
