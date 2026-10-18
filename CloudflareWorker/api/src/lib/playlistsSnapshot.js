// The playlists snapshot: every published playlist with its titles in the
// curator's order, so the shelf is one 304 instead of a request per playlist.
//
// Kept like the catalogue index: one row per version, the version a hash of
// the body, the version in a header on every response. Nothing about the
// player is in it, and no "playable": the phone takes that from the index.

import { sha256Hex } from "./crypto.js";
import { folderPostersFrom } from "./playlists.js";

export const PLAYLISTS_VERSION_HEADER = "X-Playlists-Version";

const VERSION_KEY = "playlistsSnapshotVersion";
const DIRTY_KEY = "playlistsSnapshotDirty";
const VERSION_CACHE_MS = 60 * 1000;
// Rebuilt on every curator save, and the route only serves the current one,
// so an old row only has to outlive a download already under way.
const OLD_VERSION_RETENTION_MS = 24 * 60 * 60 * 1000;

let cachedVersion = { value: null, readAt: 0 };

export async function currentPlaylistsVersion(env, { now = Date.now() } = {}) {
    if (now - cachedVersion.readAt < VERSION_CACHE_MS) return cachedVersion.value;
    const row = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(VERSION_KEY).first();
    cachedVersion = { value: row?.value ?? null, readAt: now };
    return cachedVersion.value;
}

export function forgetCachedPlaylistsVersion() {
    cachedVersion = { value: null, readAt: 0 };
}

// For writes outside the playlist routes (sync, import, a new poster) that the
// cron picks up. Flags only when the title sits in a playlist and one of the
// fields the snapshot shows would move, so it has to run before that write.
// `fillPoster` is the importer's rule: a poster is only set where none is.
export function markPlaylistsDirtyIfMovedStatement(env, mediaKey, { title, releaseYear, posterURL, fillPoster = false }) {
    const moved = [];
    const values = [];
    if (title !== undefined) {
        moved.push("m.title IS NOT ?");
        values.push(title);
    }
    if (releaseYear !== undefined) {
        moved.push("m.release_year IS NOT ?");
        values.push(releaseYear);
    }
    if (posterURL !== undefined) {
        moved.push(fillPoster ? "COALESCE(m.poster_url, ?) IS NOT m.poster_url" : "m.poster_url IS NOT ?");
        values.push(posterURL);
    }
    return env.DB.prepare(
        `INSERT INTO app_config (key, value)
         SELECT ?, '1' WHERE EXISTS (
             SELECT 1 FROM media_items m
             WHERE m.key = ? AND (${moved.join(" OR ")})
               AND EXISTS (SELECT 1 FROM playlist_items pi WHERE pi.media_key = m.key)
         )
         ON CONFLICT (key) DO UPDATE SET value = '1'`
    ).bind(DIRTY_KEY, mediaKey, ...values);
}

function postersOf(members) {
    return new Map(members.filter((item) => item.poster_url).map((item) => [item.media_key, item.poster_url]));
}

export async function buildPlaylistsBody(env) {
    const [playlists, items] = await env.DB.batch([
        env.DB.prepare(
            `SELECT id, title, description, cover_image_url, media_type, created_at, curator_order, folder_keys
             FROM playlists WHERE published = 1 ORDER BY created_at DESC, id`
        ),
        // CROSS JOIN keeps playlists outermost, so drafts' items are never read.
        env.DB.prepare(
            `SELECT pi.playlist_id, pi.media_key, pi.added_at, m.title, m.release_year, m.poster_url
             FROM playlists p
             CROSS JOIN playlist_items pi ON pi.playlist_id = p.id
             JOIN media_items m ON m.key = pi.media_key
             WHERE p.published = 1
             ORDER BY pi.playlist_id, pi.position`
        )
    ]);

    const byPlaylist = new Map();
    for (const row of items.results) {
        if (!byPlaylist.has(row.playlist_id)) byPlaylist.set(row.playlist_id, []);
        byPlaylist.get(row.playlist_id).push(row);
    }

    return JSON.stringify({
        format: 1,
        playlists: playlists.results.map((row) => {
            const members = byPlaylist.get(row.id) || [];
            return {
                id: row.id,
                title: row.title,
                description: row.description,
                coverImageURL: row.cover_image_url,
                mediaType: row.media_type,
                createdAt: row.created_at,
                orderByCurator: row.curator_order === 1,
                folderPosters: folderPostersFrom(row, postersOf(members)),
                items: members.map((item) => ({
                    key: item.media_key,
                    title: item.title,
                    releaseYear: item.release_year,
                    posterURL: item.poster_url,
                    addedAt: item.added_at ?? 0
                }))
            };
        })
    });
}

// The row first, the version second: a phone that sees the new version must
// find its body.
export async function rebuildPlaylistsSnapshot(env, { now = Date.now() } = {}) {
    const body = await buildPlaylistsBody(env);
    const version = `p1-${(await sha256Hex(body)).slice(0, 16)}`;
    const current = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(VERSION_KEY).first();

    if (current?.value !== version) {
        await env.DB.prepare("INSERT OR IGNORE INTO playlists_snapshot (version, body, created_at) VALUES (?, ?, ?)")
            .bind(version, body, now)
            .run();
        await env.DB.prepare(
            "INSERT INTO app_config (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value"
        ).bind(VERSION_KEY, version).run();
    }

    await env.DB.batch([
        env.DB.prepare("DELETE FROM app_config WHERE key = ?").bind(DIRTY_KEY),
        env.DB.prepare("DELETE FROM playlists_snapshot WHERE version != ? AND created_at < ?")
            .bind(version, now - OLD_VERSION_RETENTION_MS)
    ]);

    forgetCachedPlaylistsVersion();
    return { version, changed: current?.value !== version };
}

// For the playlist routes, after their write has committed: a failed rebuild
// must not turn a saved edit into a 500, so it is left to the cron.
export async function rebuildPlaylistsOrMarkDirty(env) {
    try {
        await rebuildPlaylistsSnapshot(env);
    } catch (error) {
        console.error("Playlists snapshot rebuild failed", error?.stack || error);
        try {
            await env.DB.prepare("INSERT INTO app_config (key, value) VALUES (?, '1') ON CONFLICT (key) DO UPDATE SET value = '1'")
                .bind(DIRTY_KEY).run();
        } catch (flagError) {
            console.error("Playlists snapshot flag failed", flagError?.message);
        }
    }
}

export async function rebuildPlaylistsIfDirty(env) {
    const [dirty, version] = await env.DB.batch([
        env.DB.prepare("SELECT 1 AS yes FROM app_config WHERE key = ?").bind(DIRTY_KEY),
        env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(VERSION_KEY)
    ]);
    if (!dirty.results.length && version.results.length) return null;
    return rebuildPlaylistsSnapshot(env);
}

export async function loadPlaylistsSnapshot(env) {
    const wanted = await currentPlaylistsVersion(env);
    if (!wanted) return null;
    return env.DB.prepare("SELECT version, body FROM playlists_snapshot WHERE version = ?").bind(wanted).first();
}
