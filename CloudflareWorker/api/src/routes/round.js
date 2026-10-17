// Picking a round.
//
// This is where the database earns its keep. Choosing a title that matches the
// filters *and* has not been seen before is one query with a WHERE clause, and
// the count of what is left is exact — no retry loop, no probabilistic "you
// have probably seen everything" hedging.

import { badRequest, json, notFound, parseInteger, readJSON } from "../lib/http.js";
import { authenticate } from "../lib/auth.js";
import { buildCatalogQuery, loadGenreIds, parseFilters, serializeImage, serializeMediaItem } from "../lib/media.js";
import { ROUND_LAYOUT_SIZE, selectRoundFrames, selectSpareFrames } from "../lib/frames.js";
import { finishRound } from "../lib/plays.js";
import { playerOrderRank } from "../lib/playlists.js";
import { dailyNumber, ensureFrozen, isValidDateString, loadDailyPlan, utcDateString } from "../lib/daily.js";

const SPARE_FRAME_COUNT = 3;

// Titles read per pick, one drawn from them. Walking from a random point favours
// whichever title follows a wide gap in shuffle_key; drawing among the next
// eight evens that out to within ~35% while still reading a handful of rows.
const SHUFFLE_SAMPLE = 8;

async function pickRandomKey(env, where, bindings) {
    const point = Math.random();
    const from = `SELECT m.key FROM media_items m INDEXED BY idx_media_shuffle WHERE ${where}`;

    const rows = (await env.DB.prepare(`${from} AND m.shuffle_key >= ? ORDER BY m.shuffle_key LIMIT ?`)
        .bind(...bindings, point, SHUFFLE_SAMPLE)
        .all()).results;

    if (rows.length < SHUFFLE_SAMPLE) {
        const wrapped = await env.DB.prepare(`${from} AND m.shuffle_key < ? ORDER BY m.shuffle_key LIMIT ?`)
            .bind(...bindings, point, SHUFFLE_SAMPLE - rows.length)
            .all();
        rows.push(...wrapped.results);
    }

    return rows.length ? rows[Math.floor(Math.random() * rows.length)].key : null;
}

async function loadItemWithFrames(env, key, frameCount) {
    const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
    if (!item) throw notFound(`Unknown media item "${key}"`);

    const images = await env.DB.prepare("SELECT * FROM media_images WHERE media_key = ? AND status = 'approved' AND missing_at IS NULL")
        .bind(key)
        .all();
    const frames = selectRoundFrames(images.results, frameCount);
    const genres = await loadGenreIds(env, [key]);

    // Sent in the same response so a frame deleted from TMDB can be swapped on
    // device without another request. A title with exactly six has no slack.
    const spares = selectSpareFrames(images.results, new Set(frames.map((frame) => frame.id)), SPARE_FRAME_COUNT);

    return {
        item: serializeMediaItem(item, genres.get(key) || []),
        frames: frames.map(serializeImage),
        spareFrames: spares.map(serializeImage)
    };
}

// Frames in the stored order, whatever their status is now: re-curating the
// film must not rewrite a day that has already been published.
async function loadFrozenDaily(env, plan, frameCount) {
    const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(plan.media_key).first();
    if (!item) throw notFound(`Unknown media item "${plan.media_key}"`);

    const frameIds = JSON.parse(plan.frame_ids).slice(0, frameCount);
    const spareIds = JSON.parse(plan.spare_ids || "[]");
    const ids = [...frameIds, ...spareIds];

    const rows = ids.length
        ? (await env.DB.prepare(
            `SELECT * FROM media_images WHERE id IN (${ids.map(() => "?").join(", ")})`
        ).bind(...ids).all()).results
        : [];

    const byId = new Map(rows.map((row) => [row.id, row]));
    const pick = (list) => list.map((id) => byId.get(id)).filter(Boolean).map(serializeImage);
    const genres = await loadGenreIds(env, [plan.media_key]);

    return {
        item: serializeMediaItem(item, genres.get(plan.media_key) || []),
        frames: pick(frameIds),
        spareFrames: pick(spareIds)
    };
}

export async function handleRound(request, env, segments, url) {
    if (segments[0] === "finish" && request.method === "POST") {
        const user = await authenticate(request, env);
        return json(await finishRound(env, user, await readJSON(request)));
    }

    if (segments[0] !== "next" || request.method !== "GET") return null;

    const user = await authenticate(request, env);
    const frameCount = parseInteger(url.searchParams.get("frameCount"), { fallback: ROUND_LAYOUT_SIZE, min: 1, max: ROUND_LAYOUT_SIZE });
    const pool = url.searchParams.get("pool") || "curated";

    // ------------------------------------------------------------- daily
    // Served from the layout frozen onto the day, so everyone gets the same six
    // frames in the same order — and the same substitute for a missing one.
    if (pool === "daily") {
        const date = url.searchParams.get("date") || utcDateString();
        if (!isValidDateString(date)) throw badRequest("date must be YYYY-MM-DD");
        if (date > utcDateString()) throw badRequest("The daily puzzle for a future date is not available");

        const plan = await loadDailyPlan(env, date);
        if (!plan) {
            // No automatic pick: it cannot honour the scheduling rules, and an
            // empty date is loud in the admin calendar where a bad day is not.
            return json(
                { error: "no_daily", date, message: "No film is scheduled for this day" },
                404
            );
        }

        const frozen = await ensureFrozen(env, plan);
        return json({
            pool: "daily",
            date,
            number: await dailyNumber(env, date),
            ...(await loadFrozenDaily(env, frozen, frameCount))
        });
    }

    // -------------------------------------- curated pool, optionally a playlist
    const filters = parseFilters(url);
    filters.minApprovedImages = frameCount;

    const playlistId = url.searchParams.get("playlistId");
    const requestedKey = url.searchParams.get("mediaKey");

    // The phone picked the title from its index. Not refused for being an
    // upcoming daily: the index cannot leave those out without naming them.
    // Anything else unplayable means the phone's index is stale.
    if (requestedKey && !playlistId) {
        const item = await env.DB.prepare("SELECT published FROM media_items WHERE key = ?").bind(requestedKey).first();
        if (item?.published !== 1) {
            return json(
                { error: "not_playable", mediaKey: requestedKey, message: "This title is not in the game any more" },
                404
            );
        }
        return json({ pool: "curated", ...(await loadItemWithFrames(env, requestedKey, frameCount)) });
    }
    const excludeWatched = url.searchParams.get("excludeWatched") !== "false";

    if (playlistId) {
        // Playlist progress is deliberately separate from the global watched
        // list: answering a title inside one playlist must not tick it off
        // inside another, or completion becomes something you can cheese by
        // playing elsewhere.
        const pick = url.searchParams.get("pick") || "next";

        const notCompleted = `NOT EXISTS (
            SELECT 1 FROM playlist_progress pr
            WHERE pr.uid = ?3 AND pr.playlist_id = ?1 AND pr.media_key = m.key AND pr.state = 'completed'
        )`;

        const from = `FROM media_items m
                      JOIN playlist_items p ON p.media_key = m.key
                      WHERE p.playlist_id = ?1 AND m.published = 1 AND m.approved_images >= ?2`;

        let row = null;

        if (requestedKey) {
            // Replaying one specific entry — how "try this one again" works.
            row = await env.DB.prepare(
                `SELECT m.key, p.position ${from} AND m.key = ?3 LIMIT 1`
            ).bind(playlistId, frameCount, requestedKey).first();

            if (!row) throw notFound("That title is not in this playlist, or has too few approved frames");
        } else {
            // A ladder rather than one query: unplayed entries first, then the
            // ones answered wrong, longest unplayed first, and once everything
            // is guessed a shuffle that keeps the recent half resting.
            //
            // Unless the curator fixed the order, "the order" is the player's
            // own: every candidate is read and the lowest stable rank wins.
            const meta = await env.DB.prepare("SELECT curator_order FROM playlists WHERE id = ?").bind(playlistId).first();
            const byCurator = meta?.curator_order === 1;
            const ordered = (condition) => byCurator
                ? { sql: `SELECT m.key, p.position ${from} AND ${condition} ORDER BY p.position LIMIT 1`, bindings: [playlistId, frameCount, user.uid] }
                : { sql: `SELECT m.key, p.position ${from} AND ${condition}`, bindings: [playlistId, frameCount, user.uid], rank: true };

            const unplayed = ordered(notCompleted);
            const played = `FROM media_items m
                            JOIN playlist_items p ON p.media_key = m.key
                            JOIN playlist_progress pr ON pr.uid = ?3 AND pr.playlist_id = p.playlist_id
                                                     AND pr.media_key = m.key AND pr.state = 'completed'
                            WHERE p.playlist_id = ?1 AND m.published = 1 AND m.approved_images >= ?2`;

            const stages = pick === "shuffle"
                ? [
                    unplayed,
                    { sql: `SELECT m.key, p.position ${played} AND pr.was_correct = 0 ORDER BY pr.updated_at, m.key LIMIT 1`, bindings: [playlistId, frameCount, user.uid] },
                    { sql: `SELECT m.key, p.position ${played} ORDER BY pr.updated_at, m.key`, bindings: [playlistId, frameCount, user.uid], rested: true }
                ]
                : [unplayed];

            for (const stage of stages) {
                if (stage.rested) {
                    const rows = (await env.DB.prepare(stage.sql).bind(...stage.bindings).all()).results;
                    const pool = rows.slice(0, Math.ceil(rows.length / 2));
                    row = pool[Math.floor(Math.random() * pool.length)] ?? null;
                } else if (stage.rank) {
                    const rows = (await env.DB.prepare(stage.sql).bind(...stage.bindings).all()).results;
                    row = rows.reduce((best, item) => !best
                        || playerOrderRank(user.uid, playlistId, item.key) < playerOrderRank(user.uid, playlistId, best.key)
                        ? item : best, null);
                } else {
                    row = await env.DB.prepare(stage.sql).bind(...stage.bindings).first();
                }
                if (row) break;
            }
        }

        if (!row) throw notFound("Nothing left to play in this playlist");

        // Counted over what can be dealt, so a title that left the game does
        // not leave "17 of 100" forever one short.
        // "17 of 100" counts what the player has answered, not where the title
        // sits in the list: in a player's own order the two have nothing in common.
        const total = await env.DB.prepare(
            `SELECT COUNT(*) AS count,
                    SUM(EXISTS (SELECT 1 FROM playlist_progress pr
                                WHERE pr.uid = ? AND pr.playlist_id = p.playlist_id
                                  AND pr.media_key = p.media_key AND pr.state = 'completed')) AS answered
             FROM playlist_items p JOIN media_items m ON m.key = p.media_key
             WHERE p.playlist_id = ? AND m.published = 1`
        ).bind(user.uid, playlistId).first();

        return json({
            pool: "playlist",
            playlistId,
            // 1-based so the client can say "17 of 100" without arithmetic.
            position: Math.min(total.count, (total.answered ?? 0) + 1),
            playlistTotal: total.count,
            ...(await loadItemWithFrames(env, row.key, frameCount))
        });
    }

    const today = utcDateString();
    const { where, bindings } = buildCatalogQuery(filters, { uid: user.uid, excludeWatched, excludeDailyFrom: today });

    const pickedKey = await pickRandomKey(env, where, bindings);

    if (!pickedKey) {
        // Distinguish "your filters match nothing" from "you have played
        // everything that matches", because those need different advice and we
        // can tell them apart exactly here.
        const ignoringWatched = buildCatalogQuery(filters, { excludeWatched: false, excludeDailyFrom: today });
        const total = await env.DB.prepare(`SELECT COUNT(*) AS count FROM media_items m WHERE ${ignoringWatched.where}`)
            .bind(...ignoringWatched.bindings)
            .first();

        return json(
            {
                error: total.count > 0 ? "pool_exhausted" : "no_matches",
                matchingTotal: total.count,
                message:
                    total.count > 0
                        ? "Everything matching these filters has already been played"
                        : "No curated titles match these filters"
            },
            404
        );
    }

    return json({ pool: "curated", ...(await loadItemWithFrames(env, pickedKey, frameCount)) });
}
