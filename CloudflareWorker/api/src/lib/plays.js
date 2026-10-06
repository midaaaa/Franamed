// A finished round: what the player has seen, the statistic it feeds, and the
// playlist or daily record it closes, in one request.
//
// The phone keeps the working copy of what was played and picks titles from
// it; this is the backup it restores from, and the source of the statistics.

import { badRequest, notFound, requireEnum, requireString } from "./http.js";
import { ROUND_LAYOUT_SIZE } from "./frames.js";
import { isValidDateString, loadDailyPlan, recordDailyResult, utcDateString } from "./daily.js";
import { recordPlaylistAnswer } from "../routes/playlists.js";

export const PLAY_MODES = ["random", "playlist", "daily"];

export function serializeWatched(row) {
    return {
        mediaKey: row.media_key,
        sources: JSON.parse(row.sources),
        addedAt: row.added_at,
        result: row.result ?? null,
        solvedAtFrame: row.solved_at_frame ?? null,
        frameCount: row.frame_count ?? null,
        mode: row.mode ?? null,
        solved: row.solved === 1,
        hidden: row.hidden === 1,
        plays: row.plays ?? 0,
        lastPlayedAt: row.last_played_at ?? null
    };
}

function parseFinish(body) {
    const mediaKey = requireString(body, "mediaKey", { maxLength: 60 });
    const mode = requireEnum(body, "mode", PLAY_MODES);
    const result = requireEnum(body, "result", ["correct", "wrong"]);

    const frameCount = Number.parseInt(body.frameCount, 10);
    if (!Number.isInteger(frameCount) || frameCount < 1 || frameCount > ROUND_LAYOUT_SIZE) {
        throw badRequest(`frameCount must be 1–${ROUND_LAYOUT_SIZE}`);
    }

    let solvedAtFrame = null;
    if (result === "correct") {
        solvedAtFrame = Number.parseInt(body.solvedAtFrame, 10);
        if (!Number.isInteger(solvedAtFrame) || solvedAtFrame < 1 || solvedAtFrame > frameCount) {
            throw badRequest("solvedAtFrame must be 1–frameCount when the answer is correct");
        }
    }
    if (body.counts !== undefined && typeof body.counts !== "boolean") throw badRequest("counts must be a boolean");

    return {
        mediaKey,
        mode,
        wasCorrect: result === "correct",
        solvedAtFrame,
        frameCount,
        // A frame that failed to load keeps the round out of the statistic.
        counts: body.counts !== false,
        // Each wrong guess opens the next frame, so attempts are frames.
        attemptsUsed: solvedAtFrame ?? frameCount
    };
}

async function markWatched(env, uid, play, { counted, now }) {
    return (await env.DB.prepare(
        `INSERT INTO watched_media (uid, media_key, sources, added_at, result, solved_at_frame, frame_count,
                                    mode, solved, plays, last_played_at)
         VALUES (?1, ?2, '["play"]', ?3, ?4, ?5, ?6, ?7, ?8, 1, ?3)
         ON CONFLICT (uid, media_key) DO UPDATE SET
            result          = CASE WHEN watched_media.plays = 0 THEN excluded.result ELSE watched_media.result END,
            solved_at_frame = CASE WHEN watched_media.plays = 0 THEN excluded.solved_at_frame ELSE watched_media.solved_at_frame END,
            frame_count     = CASE WHEN watched_media.plays = 0 THEN excluded.frame_count ELSE watched_media.frame_count END,
            mode            = CASE WHEN watched_media.plays = 0 THEN excluded.mode ELSE watched_media.mode END,
            sources = CASE WHEN EXISTS (SELECT 1 FROM json_each(watched_media.sources) WHERE value = 'play')
                           THEN watched_media.sources ELSE json_insert(watched_media.sources, '$[#]', 'play') END,
            solved = MAX(watched_media.solved, excluded.solved),
            plays = watched_media.plays + 1,
            last_played_at = excluded.last_played_at
         RETURNING *`
    ).bind(
        uid,
        play.mediaKey,
        now,
        counted ? (play.wasCorrect ? "correct" : "wrong") : null,
        counted ? play.solvedAtFrame : null,
        counted ? play.frameCount : null,
        play.mode,
        play.wasCorrect ? 1 : 0
    ).all()).results[0];
}

// How everyone else did: players counted, and how many got it at each frame.
async function titleStats(env, mediaKey) {
    const rows = await env.DB.prepare(
        `SELECT solved_at_frame AS frame, COUNT(*) AS n FROM watched_media
         WHERE media_key = ? AND result IS NOT NULL GROUP BY solved_at_frame`
    ).bind(mediaKey).all();
    return tally(rows.results);
}

async function dayStats(env, date) {
    const rows = await env.DB.prepare(
        `SELECT CASE WHEN was_correct = 1 THEN attempts_used END AS frame, COUNT(*) AS n
         FROM daily_results WHERE date = ? GROUP BY was_correct, attempts_used`
    ).bind(date).all();
    return tally(rows.results);
}

function tally(rows) {
    const solvedAtFrame = Array.from({ length: ROUND_LAYOUT_SIZE }, () => 0);
    let players = 0;
    for (const row of rows) {
        players += row.n;
        if (row.frame >= 1 && row.frame <= ROUND_LAYOUT_SIZE) solvedAtFrame[row.frame - 1] += row.n;
    }
    return { players, solvedAtFrame };
}

export async function finishRound(env, user, body) {
    const play = parseFinish(body);
    const now = Date.now();
    const response = {};

    if (play.mode === "daily") {
        const date = requireString(body, "date", { maxLength: 10 });
        if (!isValidDateString(date) || date > utcDateString()) throw badRequest("date must be a past or today's YYYY-MM-DD");

        const plan = await loadDailyPlan(env, date);
        if (!plan || plan.media_key !== play.mediaKey) throw badRequest("That is not the film of that day");

        // A day is played once: a second finish changes nothing.
        const recorded = await env.DB.prepare("SELECT * FROM daily_results WHERE uid = ? AND date = ?")
            .bind(user.uid, date)
            .first();
        if (recorded) {
            return {
                alreadyRecorded: true,
                daily: {
                    date,
                    wasCorrect: recorded.was_correct === 1,
                    attemptsUsed: recorded.attempts_used,
                    dailyStreak: user.daily_streak,
                    longestStreak: user.longest_streak
                },
                stats: await dayStats(env, date)
            };
        }

        const outcome = await recordDailyResult(env, user, {
            dateString: date,
            mediaKey: play.mediaKey,
            wasCorrect: play.wasCorrect,
            attemptsUsed: play.attemptsUsed
        });
        response.daily = { date, wasCorrect: play.wasCorrect, attemptsUsed: play.attemptsUsed, ...outcome };
    } else {
        const item = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(play.mediaKey).first();
        if (!item) throw notFound(`Unknown media item "${play.mediaKey}"`);
    }

    if (play.mode === "playlist") {
        const playlistId = requireString(body, "playlistId", { maxLength: 64 });
        const member = await env.DB.prepare("SELECT 1 AS yes FROM playlist_items WHERE playlist_id = ? AND media_key = ?")
            .bind(playlistId, play.mediaKey)
            .first();
        if (!member) throw notFound("That title is not in this playlist");

        response.playlist = await recordPlaylistAnswer(env, user, playlistId, {
            mediaKey: play.mediaKey,
            attemptsUsed: play.attemptsUsed,
            wasCorrect: play.wasCorrect
        });
    }

    const counted = play.mode !== "daily" && play.counts;
    const watched = await markWatched(env, user.uid, play, { counted, now });

    return {
        ...response,
        repeat: watched.plays > 1,
        counted: counted && watched.plays === 1,
        watched: serializeWatched(watched),
        stats: play.mode === "daily" ? await dayStats(env, response.daily.date) : await titleStats(env, play.mediaKey)
    };
}
