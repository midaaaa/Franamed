// Admin surface: roles, runtime config, scheduled dailies, onboarding pick.

import { badRequest, conflict, json, noContent, notFound, parseInteger, readJSON, requireEnum, requireString } from "../lib/http.js";
import { ROLES, authenticate, requireRole, revokeAllTokens, roleRank } from "../lib/auth.js";
import { readConfig, writeConfig } from "../lib/config.js";
import { DEFAULT_DAILY_FRAME_COUNT, freezeDailyLayout, isValidDateString, utcDateString } from "../lib/daily.js";

export async function handleAdmin(request, env, segments, url) {
    // GET /v1/admin/config is readable by any signed-in client: the app needs
    // to know how many attempts a round gets. Everything else needs a role.
    if (segments[0] === "config" && request.method === "GET") {
        await authenticate(request, env);
        return json(await readConfig(env));
    }

    const user = await authenticate(request, env);

    if (segments[0] === "config" && request.method === "PATCH") {
        requireRole(user, "admin");
        return json(await writeConfig(env, await readJSON(request)));
    }

    // POST /v1/admin/roles — invite-only promotion, admins only
    if (segments[0] === "roles" && request.method === "POST") {
        requireRole(user, "admin");
        const body = await readJSON(request);

        const uid = requireString(body, "uid", { maxLength: 64 });
        const role = requireEnum(body, "role", ROLES);

        const target = await env.DB.prepare("SELECT uid, role, is_anonymous FROM users WHERE uid = ?").bind(uid).first();
        if (!target) throw notFound("Unknown user");

        // An anonymous account is tied to one install, which is a reason to be
        // careful about powers rather than about curating: a curator's work
        // lands on a moderator's desk anyway. So the Apple requirement starts
        // at moderator, where a lost account means lost authority.
        if (roleRank(role) >= roleRank("moderator") && target.is_anonymous === 1) {
            throw badRequest("Link an Apple ID to this account before granting moderator or admin");
        }

        await env.DB.prepare("UPDATE users SET role = ? WHERE uid = ?").bind(role, uid).run();

        // Access tokens carry the old role for up to their lifetime, so any
        // step down drops the sessions.
        if (roleRank(role) < roleRank(target.role)) await revokeAllTokens(env, uid);

        return json({ uid, role });
    }

    if (segments[0] === "users" && request.method === "GET") {
        requireRole(user, "moderator");
        const rows = await env.DB.prepare(
            "SELECT uid, role, display_name, is_anonymous, created_at, daily_streak FROM users ORDER BY created_at DESC LIMIT 200"
        ).all();

        return json({
            users: rows.results.map((row) => ({
                uid: row.uid,
                role: row.role,
                displayName: row.display_name,
                isAnonymous: row.is_anonymous === 1,
                createdAt: row.created_at,
                dailyStreak: row.daily_streak
            }))
        });
    }

    // PUT /v1/admin/daily/{date} — schedule a specific film weeks ahead
    if (segments[0] === "daily" && segments.length === 2 && request.method === "PUT") {
        requireRole(user, "moderator");

        const date = segments[1];
        if (!isValidDateString(date)) throw badRequest("date must be YYYY-MM-DD");
        if (date < utcDateString()) throw badRequest("A past day cannot be changed");

        const body = await readJSON(request);
        const mediaKey = requireString(body, "mediaKey", { maxLength: 60 });
        const frameCount = parseInteger(body.frameCount, { fallback: DEFAULT_DAILY_FRAME_COUNT, min: 1, max: 12 });

        if (!mediaKey.startsWith("movie_")) {
            throw badRequest("The daily puzzle is movies only");
        }

        const config = await readConfig(env);
        const item = await env.DB.prepare("SELECT approved_images FROM media_items WHERE key = ?").bind(mediaKey).first();
        if (!item) throw notFound("Unknown media item");

        // The bar here is the curation target, not the playability threshold:
        // the one puzzle everybody plays should come from a film that was
        // actually finished, with frames to spare.
        if (item.approved_images < config.targetApprovedFrames) {
            throw badRequest(`That film needs ${config.targetApprovedFrames} approved frames, it has ${item.approved_images}`);
        }

        // A film may come round only once. Nothing enforced this before.
        const usedOn = await env.DB.prepare(
            "SELECT date FROM daily_overrides WHERE media_key = ? AND date != ?"
        ).bind(mediaKey, date).first();
        if (usedOn) throw conflict(`That film is already scheduled for ${usedOn.date}`);

        const existing = await env.DB.prepare("SELECT media_key FROM daily_overrides WHERE date = ?").bind(date).first();
        if (existing && date === utcDateString()) {
            throw conflict("Today's puzzle is already running and cannot be swapped");
        }

        await env.DB.prepare(
            `INSERT INTO daily_overrides (date, media_key, created_by, created_at)
             VALUES (?, ?, ?, ?)
             ON CONFLICT (date) DO UPDATE SET media_key = excluded.media_key, created_by = excluded.created_by`
        ).bind(date, mediaKey, user.uid, Date.now()).run();

        // Frozen at scheduling time rather than at first play, so what the day
        // will look like is visible while it can still be changed.
        const layout = await freezeDailyLayout(env, { dateString: date, mediaKey, frameCount });

        return json({ date, mediaKey, ...layout });
    }

    // DELETE /v1/admin/daily/{date} — only ahead of today: past days carry
    // results and streaks that would be orphaned.
    if (segments[0] === "daily" && segments.length === 2 && request.method === "DELETE") {
        requireRole(user, "moderator");

        const date = segments[1];
        if (!isValidDateString(date)) throw badRequest("date must be YYYY-MM-DD");
        if (date <= utcDateString()) throw badRequest("Only a future day can be removed");

        await env.DB.prepare("DELETE FROM daily_overrides WHERE date = ?").bind(date).run();
        return noContent();
    }

    if (segments[0] === "daily" && segments.length === 1 && request.method === "GET") {
        requireRole(user, "moderator");
        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 400, min: 1, max: 1000 });

        const rows = await env.DB.prepare(
            `SELECT d.date, d.media_key, d.created_by, d.frame_ids, d.frame_count, d.frozen_at, m.title, m.poster_url
             FROM daily_overrides d LEFT JOIN media_items m ON m.key = d.media_key
             ORDER BY d.date DESC LIMIT ?`
        ).bind(limit).all();

        // Numbered the way Framed does it: by position among the days that
        // exist, so a gap in the calendar does not leave a gap in the numbers.
        const ascending = [...rows.results].sort((a, b) => (a.date < b.date ? -1 : 1));
        const numbers = new Map(ascending.map((row, index) => [row.date, index + 1]));

        return json({
            schedule: rows.results.map((row) => ({
                date: row.date,
                number: numbers.get(row.date),
                mediaKey: row.media_key,
                title: row.title,
                posterURL: row.poster_url ?? null,
                frameCount: row.frame_count,
                frozen: Boolean(row.frame_ids),
                scheduledBy: row.created_by
            })),
            // Small enough to send whole, and it is what the planner needs to
            // grey out films that have already had their day.
            usedMediaKeys: rows.results.map((row) => row.media_key)
        });
    }

    // GET /v1/admin/stats — what the catalogue actually looks like right now
    if (segments[0] === "stats" && request.method === "GET") {
        requireRole(user, "moderator");

        const items = await env.DB.prepare(
            `SELECT media_type,
                    COUNT(*) AS total,
                    SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) AS approved,
                    SUM(CASE WHEN approved_images >= 6 THEN 1 ELSE 0 END) AS playable,
                    SUM(CASE WHEN admin_finalized = 1 THEN 1 ELSE 0 END) AS finalized,
                    SUM(CASE WHEN poster_url IS NOT NULL THEN 1 ELSE 0 END) AS withPoster
             FROM media_items GROUP BY media_type`
        ).all();

        const images = await env.DB.prepare(
            `SELECT status, COUNT(*) AS count FROM media_images GROUP BY status`
        ).all();

        const users = await env.DB.prepare("SELECT COUNT(*) AS count FROM users").first();
        const playlists = await env.DB.prepare("SELECT COUNT(*) AS count FROM playlists").first();

        return json({
            items: items.results,
            images: Object.fromEntries(images.results.map((row) => [row.status, row.count])),
            users: users.count,
            playlists: playlists.count
        });
    }

    return null;
}
