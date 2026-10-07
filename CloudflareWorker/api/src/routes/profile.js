// The player's own state: watched history and daily results.

import { json, noContent, parseInteger, readJSON } from "../lib/http.js";
import { authenticate, publicUser } from "../lib/auth.js";
import { deleteAccount } from "../lib/accounts.js";
import { serializeWatched } from "../lib/plays.js";
import { utcDateString } from "../lib/daily.js";

const WATCHED_SOURCES = ["play", "kinopoisk", "imdb", "letterboxd"];
const MAX_WATCHED_BATCH = 500;

export async function handleProfile(request, env, segments, url) {
    const user = await authenticate(request, env);

    // GET /v1/profile
    if (segments.length === 0 && request.method === "GET") {
        return json({ user: publicUser(user) });
    }

    // DELETE /v1/profile — the account and everything keyed to it
    if (segments.length === 0 && request.method === "DELETE") {
        await deleteAccount(env, user);
        return noContent();
    }

    // GET /v1/profile/watched
    if (segments[0] === "watched" && request.method === "GET") {
        const since = parseInteger(url.searchParams.get("since"), { fallback: 0, min: 0 });
        const rows = await env.DB.prepare(
            "SELECT * FROM watched_media WHERE uid = ? AND added_at > ? ORDER BY added_at"
        ).bind(user.uid, since).all();

        return json({ watched: rows.results.map(serializeWatched) });
    }

    // PATCH /v1/profile/watched/{mediaKey} — {hidden}: "do not show this again"
    if (segments[0] === "watched" && segments.length === 2 && request.method === "PATCH") {
        const body = await readJSON(request);
        if (typeof body.hidden !== "boolean") throw badRequest("hidden must be a boolean");

        const row = (await env.DB.prepare(
            `INSERT INTO watched_media (uid, media_key, sources, added_at, hidden) VALUES (?, ?, '[]', ?, ?)
             ON CONFLICT (uid, media_key) DO UPDATE SET hidden = excluded.hidden
             RETURNING *`
        ).bind(user.uid, segments[1].slice(0, 60), Date.now(), body.hidden ? 1 : 0).all()).results[0];

        return json(serializeWatched(row));
    }

    // POST /v1/profile/watched — push what the device recorded while offline
    if (segments[0] === "watched" && request.method === "POST") {
        const body = await readJSON(request);
        const items = Array.isArray(body.items) ? body.items : [];

        if (!items.length) throw badRequest("items must be a non-empty array");
        if (items.length > MAX_WATCHED_BATCH) throw badRequest(`At most ${MAX_WATCHED_BATCH} items per request`);

        const statements = items.map((item) => {
            if (typeof item.mediaKey !== "string") throw badRequest("Each item needs a mediaKey");
            const sources = Array.isArray(item.sources)
                ? item.sources.filter((source) => WATCHED_SOURCES.includes(source))
                : ["play"];

            // Re-adding a title updates it in place. The list is a set of
            // "already seen these frames", so last write wins is exactly right.
            return env.DB.prepare(
                `INSERT INTO watched_media (uid, media_key, sources, added_at)
                 VALUES (?, ?, ?, ?)
                 ON CONFLICT (uid, media_key) DO UPDATE SET sources = excluded.sources`
            ).bind(user.uid, item.mediaKey, JSON.stringify(sources.length ? sources : ["play"]), item.addedAt || Date.now());
        });

        await env.DB.batch(statements);
        return json({ synced: statements.length });
    }

    // DELETE /v1/profile/watched — the "let me see everything again" reset
    if (segments[0] === "watched" && request.method === "DELETE") {
        const source = url.searchParams.get("source");

        if (source) {
            // Re-importing a list must drop titles the user removed there, so
            // a single source can be stripped without touching play history.
            if (!WATCHED_SOURCES.includes(source)) throw badRequest("Unknown source");
            const rows = await env.DB.prepare("SELECT media_key, sources FROM watched_media WHERE uid = ?")
                .bind(user.uid)
                .all();

            const statements = [];
            for (const row of rows.results) {
                const sources = JSON.parse(row.sources).filter((entry) => entry !== source);
                statements.push(
                    sources.length
                        ? env.DB.prepare("UPDATE watched_media SET sources = ? WHERE uid = ? AND media_key = ?")
                              .bind(JSON.stringify(sources), user.uid, row.media_key)
                        : env.DB.prepare("DELETE FROM watched_media WHERE uid = ? AND media_key = ?")
                              .bind(user.uid, row.media_key)
                );
            }
            if (statements.length) await env.DB.batch(statements);
            return noContent();
        }

        await env.DB.prepare("DELETE FROM watched_media WHERE uid = ?").bind(user.uid).run();
        return noContent();
    }

    // GET /v1/profile/daily — today's status plus the archive
    if (segments[0] === "daily" && request.method === "GET") {
        const rows = await env.DB.prepare(
            "SELECT date, media_key, was_correct, attempts_used, completed_at FROM daily_results WHERE uid = ? ORDER BY date DESC LIMIT 365"
        ).bind(user.uid).all();

        const today = utcDateString();

        return json({
            today,
            playedToday: rows.results.some((row) => row.date === today),
            dailyStreak: user.daily_streak,
            longestStreak: user.longest_streak,
            history: rows.results.map((row) => ({
                date: row.date,
                mediaKey: row.media_key,
                wasCorrect: row.was_correct === 1,
                attemptsUsed: row.attempts_used,
                completedAt: row.completed_at
            }))
        });
    }

    return null;
}
