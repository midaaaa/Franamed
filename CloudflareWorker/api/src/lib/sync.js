// Keeping the catalogue in step with TMDB on the cron trigger.
//
// TMDB's terms forbid keeping its data longer than six months, and ratings
// move, so each title is fetched again: every two weeks in its first year,
// every three months after. The title's own fields are rewritten; its frames
// are not, since a re-sync must never touch curation. New stills arrive as
// unjudged, and a still TMDB no longer lists is checked against the image host
// and marked missing on a 404 rather than deleted.

import { refreshMediaCounters } from "./media.js";
import { cleanBackdrops, releaseYear, tmdbFetch } from "./tmdb.js";
import { INDEX_STEPS, markIndexDirty, stepDown } from "./catalogIndex.js";
import { replaceMissingDailyFrames } from "./daily.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const RECENT_SYNC_MS = 14 * DAY_MS;
const OLD_SYNC_MS = 90 * DAY_MS;

// A run gets 50 D1 queries and 50 outside requests; a title costs about a
// dozen of the first, so a few titles a run, and image checks share the rest.
export const SYNC_TITLES_PER_RUN = 2;
const OUTSIDE_REQUESTS_PER_RUN = 40;

// Multi-row inserts, kept under D1's 100 bound parameters.
const INSERT_CHUNK = 12;

const IMAGE_CHECK_ORIGIN = "https://image.tmdb.org/t/p/w92";

export async function syncDueTitles(env, { now = Date.now(), limit = SYNC_TITLES_PER_RUN } = {}) {
    const recentYear = new Date(now).getUTCFullYear() - 1;
    const due = await env.DB.prepare(
        `SELECT * FROM media_items INDEXED BY idx_media_synced
         WHERE last_synced_at < ?1 AND (last_synced_at < ?2 OR release_year >= ?3)
         ORDER BY last_synced_at LIMIT ?4`
    ).bind(now - RECENT_SYNC_MS, now - OLD_SYNC_MS, recentYear, limit).all();

    if (!due.results.length) return null;

    const budget = { requests: OUTSIDE_REQUESTS_PER_RUN };
    const synced = [];
    for (const item of due.results) {
        if (budget.requests <= 0) break;
        synced.push(await syncTitle(env, item, { budget, now, recent: item.release_year >= recentYear }));
    }
    return { synced };
}

async function syncTitle(env, item, { budget, now, recent }) {
    const key = item.key;
    let details;
    try {
        budget.requests -= 1;
        details = await tmdbFetch(env, `/${item.media_type}/${item.tmdb_id}`, {
            language: "ru-RU",
            append_to_response: "images",
            include_image_language: "null"
        });
    } catch (error) {
        // Tried again in a day rather than at once, so a title TMDB lost does
        // not hold the head of the queue.
        const retryAt = now - (recent ? RECENT_SYNC_MS : OLD_SYNC_MS) + DAY_MS;
        await env.DB.prepare("UPDATE media_items SET last_synced_at = ? WHERE key = ?").bind(retryAt, key).run();
        return { key, error: error.tmdbStatus ?? error.message };
    }

    const [frames, genres] = await env.DB.batch([
        env.DB.prepare("SELECT * FROM media_images WHERE media_key = ?").bind(key),
        env.DB.prepare("SELECT genre_id FROM media_genres WHERE media_key = ?").bind(key)
    ]);

    // ------------------------------------------------------------ frames
    const listed = new Map(cleanBackdrops(details).map((backdrop) => [backdrop.file_path, backdrop]));
    const known = new Map(frames.results.map((frame) => [frame.file_path, frame]));

    const added = [...listed.values()].filter((backdrop) => !known.has(backdrop.file_path));
    const returned = frames.results.filter((frame) => frame.missing_at !== null && frame.removed_at === null && listed.has(frame.file_path));

    // Approved first: those are the ones a player would hit.
    const suspects = frames.results
        .filter((frame) => !listed.has(frame.file_path) && frame.missing_at === null && frame.removed_at === null && frame.status !== "rejected")
        .sort((a, b) => (a.status === "approved" ? 0 : 1) - (b.status === "approved" ? 0 : 1));

    const gone = [];
    let checked = 0;
    for (const frame of suspects) {
        if (budget.requests <= 0) break;
        budget.requests -= 1;
        checked += 1;
        try {
            const response = await fetch(`${IMAGE_CHECK_ORIGIN}${frame.file_path}`, { method: "HEAD" });
            if (response.status === 404) gone.push(frame);
        } catch {
            // A network failure says nothing about the image.
            checked -= 1;
        }
    }
    const complete = checked === suspects.length;

    // ------------------------------------------------------------ writes
    const statements = [];
    const year = releaseYear(details, item.media_type);
    const voteAverage = details.vote_average ?? 0;
    const voteCount = details.vote_count ?? 0;

    statements.push(env.DB.prepare(
        `UPDATE media_items
         SET title = ?, original_title = ?, release_year = ?, original_language = ?, popularity = ?,
             vote_average = ?, vote_count = ?${complete ? ", last_synced_at = ?" : ""}
         WHERE key = ?`
    ).bind(
        (item.media_type === "movie" ? details.title : details.name) || item.title,
        (item.media_type === "movie" ? details.original_title : details.original_name) || item.original_title,
        year,
        details.original_language || null,
        details.popularity || 0,
        voteAverage,
        voteCount,
        ...(complete ? [now] : []),
        key
    ));

    const oldGenres = new Set(genres.results.map((row) => row.genre_id));
    const newGenres = new Set((details.genres || []).map((genre) => genre.id));
    const genresMoved = oldGenres.size !== newGenres.size || [...newGenres].some((id) => !oldGenres.has(id));
    if (genresMoved) {
        statements.push(env.DB.prepare("DELETE FROM media_genres WHERE media_key = ?").bind(key));
        for (const id of newGenres) {
            statements.push(env.DB.prepare("INSERT INTO media_genres (media_key, genre_id) VALUES (?, ?)").bind(key, id));
        }
    }

    for (let start = 0; start < added.length; start += INSERT_CHUNK) {
        const chunk = added.slice(start, start + INSERT_CHUNK);
        statements.push(env.DB.prepare(
            `INSERT OR IGNORE INTO media_images (media_key, file_path, tmdb_vote_average, tmdb_vote_count,
                                                 width, height, aspect_ratio, created_at)
             VALUES ${chunk.map(() => "(?, ?, ?, ?, ?, ?, ?, ?)").join(", ")}`
        ).bind(...chunk.flatMap((backdrop) => [
            key,
            backdrop.file_path,
            backdrop.vote_average || 0,
            backdrop.vote_count || 0,
            backdrop.width || null,
            backdrop.height || null,
            backdrop.aspect_ratio || null,
            now
        ])));
    }

    const setMissing = (ids, value) => {
        for (let start = 0; start < ids.length; start += 90) {
            const chunk = ids.slice(start, start + 90);
            statements.push(env.DB.prepare(
                `UPDATE media_images SET missing_at = ? WHERE id IN (${chunk.map(() => "?").join(", ")})`
            ).bind(value, ...chunk));
        }
    };
    setMissing(returned.map((frame) => frame.id), null);
    setMissing(gone.map((frame) => frame.id), now);

    await env.DB.batch(statements);
    await refreshMediaCounters(env, key);

    // The phone filters on these, so a published title that moved needs a new index.
    const indexMoved = genresMoved
        || year !== item.release_year
        || (details.original_language || null) !== item.original_language
        || stepDown(voteAverage, INDEX_STEPS.rating) !== stepDown(item.vote_average ?? 0, INDEX_STEPS.rating)
        || Math.min(INDEX_STEPS.votesCap, stepDown(voteCount, INDEX_STEPS.votes))
            !== Math.min(INDEX_STEPS.votesCap, stepDown(item.vote_count ?? 0, INDEX_STEPS.votes));
    if (indexMoved && item.published === 1) await markIndexDirty(env);

    let dailiesRepaired = 0;
    if (gone.length) {
        const missingIds = new Set(gone.map((frame) => frame.id));
        const returnedIds = new Set(returned.map((frame) => frame.id));
        const images = frames.results.map((frame) => ({
            ...frame,
            missing_at: missingIds.has(frame.id) ? now : returnedIds.has(frame.id) ? null : frame.missing_at
        }));
        dailiesRepaired = await replaceMissingDailyFrames(env, key, images, { now });
    }

    return {
        key,
        added: added.length,
        returned: returned.length,
        missing: gone.length,
        complete,
        dailiesRepaired
    };
}
