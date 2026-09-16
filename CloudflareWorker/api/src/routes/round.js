// Picking a round.
//
// This is where the database earns its keep. Choosing a title that matches the
// filters *and* has not been seen before is one query with a WHERE clause, and
// the count of what is left is exact — no retry loop, no probabilistic "you
// have probably seen everything" hedging.

import { badRequest, json, notFound, parseInteger } from "../lib/http.js";
import { authenticate } from "../lib/auth.js";
import { buildCatalogQuery, loadGenreIds, parseFilters, serializeImage, serializeMediaItem } from "../lib/media.js";
import { selectRoundFrames, selectSpareFrames } from "../lib/frames.js";
import { dailyNumber, ensureFrozen, isValidDateString, loadDailyPlan, utcDateString } from "../lib/daily.js";

const SPARE_FRAME_COUNT = 3;

async function loadItemWithFrames(env, key, frameCount) {
    const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
    if (!item) throw notFound(`Unknown media item "${key}"`);

    const images = await env.DB.prepare("SELECT * FROM media_images WHERE media_key = ?").bind(key).all();
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
    if (segments[0] !== "next" || request.method !== "GET") return null;

    const user = await authenticate(request, env);
    const frameCount = parseInteger(url.searchParams.get("frameCount"), { fallback: 6, min: 1, max: 12 });
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
    const excludeWatched = url.searchParams.get("excludeWatched") !== "false";

    if (playlistId) {
        // Playlist progress is deliberately separate from the global watched
        // list: answering a title inside one playlist must not tick it off
        // inside another, or completion becomes something you can cheese by
        // playing elsewhere.
        const pick = url.searchParams.get("pick") || "next";
        const requestedKey = url.searchParams.get("mediaKey");

        const notCompleted = `NOT EXISTS (
            SELECT 1 FROM playlist_progress pr
            WHERE pr.uid = ?3 AND pr.playlist_id = ?1 AND pr.media_key = m.key AND pr.state = 'completed'
        )`;

        const answeredWrong = `EXISTS (
            SELECT 1 FROM playlist_progress pr
            WHERE pr.uid = ?3 AND pr.playlist_id = ?1 AND pr.media_key = m.key
              AND pr.state = 'completed' AND pr.was_correct = 0
        )`;

        const from = `FROM media_items m
                      JOIN playlist_items p ON p.media_key = m.key
                      WHERE p.playlist_id = ?1 AND m.approved_images >= ?2`;

        let row = null;

        if (requestedKey) {
            // Replaying one specific entry — how "try this one again" works.
            row = await env.DB.prepare(
                `SELECT m.key, p.position ${from} AND m.key = ?3 LIMIT 1`
            ).bind(playlistId, frameCount, requestedKey).first();

            if (!row) throw notFound("That title is not in this playlist, or has too few approved frames");
        } else {
            // A ladder rather than one query: unplayed entries in the order the
            // curator arranged them, then the ones answered wrong, and only
            // once everything is answered correctly does it become a genuine
            // shuffle for open-ended replay.
            const unplayed = {
                sql: `SELECT m.key, p.position ${from} AND ${notCompleted} ORDER BY p.position LIMIT 1`,
                bindings: [playlistId, frameCount, user.uid]
            };

            const stages = pick === "shuffle"
                ? [
                    unplayed,
                    {
                        sql: `SELECT m.key, p.position ${from} AND ${answeredWrong} ORDER BY p.position LIMIT 1`,
                        bindings: [playlistId, frameCount, user.uid]
                    },
                    {
                        sql: `SELECT m.key, p.position ${from} ORDER BY RANDOM() LIMIT 1`,
                        bindings: [playlistId, frameCount]
                    }
                ]
                : [unplayed];

            for (const stage of stages) {
                row = await env.DB.prepare(stage.sql).bind(...stage.bindings).first();
                if (row) break;
            }
        }

        if (!row) throw notFound("Nothing left to play in this playlist");

        const total = await env.DB.prepare(
            "SELECT COUNT(*) AS count FROM playlist_items WHERE playlist_id = ?"
        ).bind(playlistId).first();

        return json({
            pool: "playlist",
            playlistId,
            // 1-based so the client can say "17 of 100" without arithmetic.
            position: row.position + 1,
            playlistTotal: total.count,
            ...(await loadItemWithFrames(env, row.key, frameCount))
        });
    }

    const { where, bindings } = buildCatalogQuery(filters, { uid: user.uid, excludeWatched });

    const picked = await env.DB.prepare(`SELECT m.key FROM media_items m WHERE ${where} ORDER BY RANDOM() LIMIT 1`)
        .bind(...bindings)
        .first();

    if (!picked) {
        // Distinguish "your filters match nothing" from "you have played
        // everything that matches", because those need different advice and we
        // can tell them apart exactly here.
        const ignoringWatched = buildCatalogQuery(filters, { excludeWatched: false });
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

    return json({ pool: "curated", ...(await loadItemWithFrames(env, picked.key, frameCount)) });
}
