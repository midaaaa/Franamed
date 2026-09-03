// Admin surface: roles, runtime config, scheduled dailies, onboarding pick.

import { badRequest, json, notFound, readJSON, requireEnum, requireString } from "../lib/http.js";
import { authenticate, requireRole, revokeAllTokens } from "../lib/auth.js";
import { readConfig, writeConfig } from "../lib/config.js";
import { isValidDateString } from "../lib/daily.js";

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
        const role = requireEnum(body, "role", ["user", "moderator", "admin"]);

        const target = await env.DB.prepare("SELECT uid, is_anonymous FROM users WHERE uid = ?").bind(uid).first();
        if (!target) throw notFound("Unknown user");

        // An anonymous account is tied to one install: reinstall the app and the
        // role is gone with no way to recover it. Curators sign in with Apple
        // first so the account outlives the device.
        if (role !== "user" && target.is_anonymous === 1) {
            throw badRequest("Link an Apple ID to this account before granting a role");
        }

        await env.DB.prepare("UPDATE users SET role = ? WHERE uid = ?").bind(role, uid).run();

        // Access tokens carry the old role for up to their lifetime; dropping
        // the sessions makes a demotion take effect at once.
        if (role === "user") await revokeAllTokens(env, uid);

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

        const body = await readJSON(request);
        const mediaKey = requireString(body, "mediaKey", { maxLength: 60 });

        if (!mediaKey.startsWith("movie_")) {
            throw badRequest("The daily puzzle is movies only");
        }

        const item = await env.DB.prepare("SELECT approved_images FROM media_items WHERE key = ?").bind(mediaKey).first();
        if (!item) throw notFound("Unknown media item");
        if (item.approved_images < 6) throw badRequest("That film does not have six approved frames yet");

        await env.DB.prepare(
            `INSERT INTO daily_overrides (date, media_key, created_by, created_at)
             VALUES (?, ?, ?, ?)
             ON CONFLICT (date) DO UPDATE SET media_key = excluded.media_key, created_by = excluded.created_by`
        ).bind(date, mediaKey, user.uid, Date.now()).run();

        return json({ date, mediaKey });
    }

    if (segments[0] === "daily" && segments.length === 1 && request.method === "GET") {
        requireRole(user, "moderator");
        const rows = await env.DB.prepare(
            `SELECT d.date, d.media_key, d.created_by, m.title
             FROM daily_overrides d LEFT JOIN media_items m ON m.key = d.media_key
             ORDER BY d.date DESC LIMIT 120`
        ).all();

        return json({
            schedule: rows.results.map((row) => ({
                date: row.date,
                mediaKey: row.media_key,
                title: row.title,
                scheduledBy: row.created_by
            }))
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
