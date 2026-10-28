// Curated collections and a player's progress through them.
//
// Progress is reported as two separate numbers — how much of the list has been
// played, and how much of what was played was right. Folding those into one
// fraction produces a figure nobody can interpret.

import { badRequest, json, noContent, notFound, readJSON, requireEnum, requireString, optionalString } from "../lib/http.js";
import { authenticate, requireRole } from "../lib/auth.js";
import { MEDIA_TYPES } from "../lib/media.js";
import {
    MAX_FOLDER_POSTERS,
    folderPosters,
    folderPostersFrom,
    parseFolderKeys,
    playerOrderRank,
    progressSummary,
    refreshFolder,
    summarizeProgress
} from "../lib/playlists.js";
import {
    PLAYLISTS_VERSION_HEADER,
    currentPlaylistsVersion,
    loadPlaylistsSnapshot,
    rebuildPlaylistsOrMarkDirty,
    rebuildPlaylistsSnapshot
} from "../lib/playlistsSnapshot.js";

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
        createdAt: row.created_at,
        folderKeys: parseFolderKeys(row),
        folderAuto: row.folder_auto === 1,
        orderByCurator: row.curator_order === 1
    };
}

async function serializeWithFolder(env, row) {
    return { ...serializePlaylist(row), folderPosters: await folderPosters(env, row) };
}

// What the snapshot shows of a playlist row; a write that moves none of these
// on a playlist that is not or was not published leaves the snapshot alone.
const SNAPSHOT_COLUMNS = ["published", "title", "description", "cover_image_url", "curator_order", "folder_keys"];

function snapshotMoved(before, after) {
    if (before.published !== 1 && after.published !== 1) return false;
    return SNAPSHOT_COLUMNS.some((column) => (before[column] ?? null) !== (after[column] ?? null));
}

// A playlist is a curated 1-to-100 walk, so this only bounds the write.
const MAX_PLAYLIST_ITEMS = 500;

export async function handlePlaylists(request, env, segments, url) {
    // GET /v1/playlists
    if (segments.length === 0 && request.method === "GET") {
        const user = await authenticate(request, env);
        const mediaType = url.searchParams.get("mediaType");
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");

        const includeUnpublished = user.role !== "user" && url.searchParams.get("includeUnpublished") === "true";

        // Every playlist's members and the player's rows in one batch, matched
        // here: the catalogue and the player tables are never joined.
        const listed = "(?1 IS NULL OR media_type = ?1) AND (published = 1 OR ?2)";
        const [rows, members, progress, completions] = await env.DB.batch([
            env.DB.prepare(`SELECT * FROM playlists WHERE ${listed} ORDER BY created_at DESC`).bind(mediaType || null, includeUnpublished ? 1 : 0),
            env.DB.prepare(
                `SELECT pi.playlist_id, pi.media_key, pi.added_at, m.poster_url, m.published
                 FROM playlist_items pi JOIN media_items m ON m.key = pi.media_key
                 WHERE pi.playlist_id IN (SELECT id FROM playlists WHERE ${listed})`
            ).bind(mediaType || null, includeUnpublished ? 1 : 0),
            env.DB.prepare(
                "SELECT playlist_id, media_key, was_correct FROM playlist_progress WHERE uid = ? AND state = 'completed'"
            ).bind(user.uid),
            env.DB.prepare("SELECT playlist_id, times_completed, completed_at FROM playlist_completions WHERE uid = ?")
                .bind(user.uid)
        ]);

        const group = (list) => {
            const grouped = new Map();
            for (const item of list) {
                if (!grouped.has(item.playlist_id)) grouped.set(item.playlist_id, []);
                grouped.get(item.playlist_id).push(item);
            }
            return grouped;
        };
        const membersOf = group(members.results);
        const progressOf = group(progress.results);
        const completionOf = new Map(completions.results.map((item) => [item.playlist_id, item]));

        const playlists = rows.results.map((row) => {
            const own = membersOf.get(row.id) || [];
            const playable = own.filter((item) => item.published === 1);
            const posters = new Map(own.filter((item) => item.poster_url).map((item) => [item.media_key, item.poster_url]));
            return {
                ...serializePlaylist(row),
                folderPosters: folderPostersFrom(row, posters),
                itemsAddedAt: playable.map((item) => item.added_at ?? 0),
                progress: summarizeProgress(
                    new Set(playable.map((item) => item.media_key)),
                    progressOf.get(row.id) || [],
                    completionOf.get(row.id)
                )
            };
        });
        return json({ playlists });
    }

    // GET /v1/playlists/snapshot — every published playlist and its titles; the
    // version is in the body and in the header every response carries
    if (segments[0] === "snapshot" && segments.length === 1 && request.method === "GET") {
        await authenticate(request, env);

        // The phone that holds the current version is answered without the body row.
        const held = await currentPlaylistsVersion(env);
        if (held && request.headers.get("If-None-Match") === `"${held}"`) {
            return new Response(null, { status: 304, headers: { ETag: `"${held}"` } });
        }

        let snapshot = await loadPlaylistsSnapshot(env);
        if (!snapshot) {
            await rebuildPlaylistsSnapshot(env);
            snapshot = await loadPlaylistsSnapshot(env);
        }

        if (request.headers.get("If-None-Match") === `"${snapshot.version}"`) {
            return new Response(null, { status: 304, headers: { ETag: `"${snapshot.version}"` } });
        }
        return new Response(`{"version":${JSON.stringify(snapshot.version)},${snapshot.body.slice(1)}`, {
            status: 200,
            headers: {
                "Content-Type": "application/json; charset=utf-8",
                ETag: `"${snapshot.version}"`,
                [PLAYLISTS_VERSION_HEADER]: snapshot.version
            }
        });
    }

    // GET /v1/playlists/progress — the player's answers and completions across
    // every playlist; the phone matches them against the snapshot and the index
    if (segments[0] === "progress" && segments.length === 1 && request.method === "GET") {
        const user = await authenticate(request, env);

        const [answers, completions] = await env.DB.batch([
            env.DB.prepare(
                `SELECT playlist_id, media_key, attempts_used, was_correct, updated_at
                 FROM playlist_progress WHERE uid = ? AND state = 'completed'`
            ).bind(user.uid),
            env.DB.prepare("SELECT playlist_id, times_completed, completed_at FROM playlist_completions WHERE uid = ?")
                .bind(user.uid)
        ]);

        return json({
            answers: answers.results.map((row) => ({
                playlistId: row.playlist_id,
                mediaKey: row.media_key,
                attemptsUsed: row.attempts_used,
                wasCorrect: row.was_correct === null ? null : row.was_correct === 1,
                updatedAt: row.updated_at
            })),
            completions: completions.results.map((row) => ({
                playlistId: row.playlist_id,
                timesCompleted: row.times_completed,
                completedAt: row.completed_at
            }))
        });
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
            requireString(body, "title", { maxLength: 50 }),
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
            `SELECT m.key, m.title, m.release_year, m.poster_url, m.approved_images, m.published, pi.added_at,
                    pr.state, pr.attempts_used, pr.was_correct
             FROM playlist_items pi
             JOIN media_items m ON m.key = pi.media_key
             LEFT JOIN playlist_progress pr
               ON pr.media_key = pi.media_key AND pr.playlist_id = pi.playlist_id AND pr.uid = ?
             WHERE pi.playlist_id = ?
             ORDER BY pi.position`
        ).bind(user.uid, playlistId).all();

        // ?order=player lists the titles in the order this player is dealt them,
        // so "next" on the grid is the round they get. Curation keeps its own order.
        const rows = url.searchParams.get("order") === "player" && playlist.curator_order !== 1
            ? [...items.results].sort((a, b) => playerOrderRank(user.uid, playlistId, a.key) - playerOrderRank(user.uid, playlistId, b.key))
            : items.results;

        return json({
            ...(await serializeWithFolder(env, playlist)),
            progress: await progressSummary(env, user.uid, playlistId),
            items: rows.map((row) => ({
                key: row.key,
                title: row.title,
                releaseYear: row.release_year,
                posterURL: row.poster_url,
                approvedImages: row.approved_images,
                playable: row.published === 1,
                addedAt: row.added_at ?? 0,
                state: row.state || "notStarted",
                attemptsUsed: row.attempts_used ?? 0,
                wasCorrect: row.was_correct === null || row.was_correct === undefined ? null : row.was_correct === 1
            }))
        });
    }

    // DELETE /v1/playlists/{id} — a draft by a moderator; a published one takes an
    // admin, since players lose their progress through it
    if (segments.length === 1 && request.method === "DELETE") {
        const user = await authenticate(request, env);
        requireRole(user, playlist.published === 1 ? "admin" : "moderator");

        // Progress rows carry no foreign key to the playlist, so they go by hand.
        await env.DB.batch([
            env.DB.prepare("DELETE FROM playlist_progress WHERE playlist_id = ?").bind(playlistId),
            env.DB.prepare("DELETE FROM playlist_completions WHERE playlist_id = ?").bind(playlistId),
            env.DB.prepare("DELETE FROM playlists WHERE id = ?").bind(playlistId)
        ]);
        if (playlist.published === 1) await rebuildPlaylistsOrMarkDirty(env);
        return noContent();
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
            const members = await env.DB.prepare(
                `SELECT MAX(m.poster_url IS NOT NULL) AS hasPoster, MAX(m.published = 1) AS hasPlayable
                 FROM playlist_items pi
                 JOIN media_items m ON m.key = pi.media_key
                 WHERE pi.playlist_id = ?`
            ).bind(playlistId).first();

            if (!members?.hasPoster && !(body.coverImageURL || playlist.cover_image_url)) {
                throw badRequest("Publishing needs a cover image or at least one title with a poster");
            }

            // Only when it goes live: a published list that loses its last
            // playable title stays published, and the phone hides it on its own.
            if (playlist.published !== 1 && !members?.hasPlayable) {
                throw badRequest("Publishing needs at least one playable title");
            }
        }

        // folderKeys: 1-3 titles of this list that have posters, cover first —
        // the curator's pick, kept as is. null hands the folder back to the server.
        let folderKeys;
        if (Array.isArray(body.folderKeys)) {
            const keys = [...new Set(body.folderKeys.filter((key) => typeof key === "string"))];
            if (keys.length === 0 || keys.length > MAX_FOLDER_POSTERS) {
                throw badRequest(`A folder shows 1 to ${MAX_FOLDER_POSTERS} posters`);
            }
            const members = await env.DB.prepare(
                `SELECT pi.media_key FROM playlist_items pi JOIN media_items m ON m.key = pi.media_key
                 WHERE pi.playlist_id = ? AND m.poster_url IS NOT NULL`
            ).bind(playlistId).all();
            const allowed = new Set(members.results.map((row) => row.media_key));
            const stranger = keys.find((key) => !allowed.has(key));
            if (stranger) throw badRequest(`"${stranger}" is not a title with a poster in this playlist`);
            folderKeys = keys;
        }

        await env.DB.prepare(
            `UPDATE playlists SET
                title = COALESCE(?, title),
                description = COALESCE(?, description),
                cover_image_url = COALESCE(?, cover_image_url),
                allow_uncurated = COALESCE(?, allow_uncurated),
                published = COALESCE(?, published),
                curator_order = COALESCE(?, curator_order),
                folder_keys = CASE WHEN ? THEN ? ELSE folder_keys END,
                folder_auto = CASE WHEN ? THEN 0 ELSE folder_auto END
             WHERE id = ?`
        ).bind(
            optionalString(body, "title", { maxLength: 50 }),
            optionalString(body, "description", { maxLength: 1000 }),
            optionalString(body, "coverImageURL", { maxLength: 500 }),
            typeof body.allowUncurated === "boolean" ? (body.allowUncurated ? 1 : 0) : null,
            typeof body.published === "boolean" ? (body.published ? 1 : 0) : null,
            typeof body.orderByCurator === "boolean" ? (body.orderByCurator ? 1 : 0) : null,
            folderKeys ? 1 : 0,
            folderKeys ? JSON.stringify(folderKeys) : null,
            folderKeys ? 1 : 0,
            playlistId
        ).run();

        if (body.folderKeys === null) {
            await refreshFolder(env, playlistId, { force: true });
        } else if (body.published === true) {
            await refreshFolder(env, playlistId);
        }

        const row = await env.DB.prepare("SELECT * FROM playlists WHERE id = ?").bind(playlistId).first();
        if (snapshotMoved(playlist, row)) await rebuildPlaylistsOrMarkDirty(env);
        return json(await serializeWithFolder(env, row));
    }

    // PUT /v1/playlists/{id}/items — replace the contents wholesale
    if (segments[1] === "items" && request.method === "PUT") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const body = await readJSON(request);
        const submitted = Array.isArray(body.mediaKeys) ? body.mediaKeys.filter((key) => typeof key === "string") : [];

        if (submitted.length > MAX_PLAYLIST_ITEMS) {
            throw badRequest(`A playlist holds at most ${MAX_PLAYLIST_ITEMS} titles`);
        }

        // Deduplicated rather than rejected: the same key twice is a client
        // slip, not a reason to fail the save. The first position wins.
        const seen = new Set();
        const keys = [];
        for (const key of submitted) {
            if (seen.has(key)) continue;
            seen.add(key);
            keys.push(key);
        }

        const wrongType = keys.find((key) => !key.startsWith(`${playlist.media_type}_`));
        if (wrongType) throw badRequest(`"${wrongType}" is not a ${playlist.media_type}; playlists hold a single media type`);

        // A title keeps the moment it first joined, so reordering or re-saving
        // the list does not make old titles look new to players.
        const existing = await env.DB.prepare(
            "SELECT media_key, added_at FROM playlist_items WHERE playlist_id = ? ORDER BY position"
        ).bind(playlistId).all();
        const joined = new Map(existing.results.map((row) => [row.media_key, row.added_at]));
        const savedAt = Date.now();

        // One batch, which D1 runs as a transaction: run separately, any failed
        // insert leaves the playlist emptied by a DELETE that already committed.
        await env.DB.batch([
            env.DB.prepare("DELETE FROM playlist_items WHERE playlist_id = ?").bind(playlistId),
            ...keys.map((key, index) =>
                env.DB.prepare("INSERT INTO playlist_items (playlist_id, media_key, position, added_at) VALUES (?, ?, ?, ?)")
                    .bind(playlistId, key, index, joined.has(key) ? joined.get(key) : savedAt)
            )
        ]);
        const folderMoved = await refreshFolder(env, playlistId);

        const reordered = existing.results.length !== keys.length
            || existing.results.some((row, index) => row.media_key !== keys[index]);
        if (playlist.published === 1 && (reordered || folderMoved)) await rebuildPlaylistsOrMarkDirty(env);

        return json({ id: playlistId, count: keys.length, duplicatesDropped: submitted.length - keys.length });
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
