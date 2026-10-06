// The catalogue index: every published title without its name, so the phone
// can count the pool and pick a title itself and only asks for frames.
//
// Stored in D1 as one row per version, the version being a hash of the body:
// a download is one row read, and rebuilding an unchanged catalogue writes
// nothing. The version travels in a header on every response, so the phone
// learns about a new one without polling.

import { sha256Hex } from "./crypto.js";

export const CATALOG_VERSION_HEADER = "X-Catalog-Version";

// Rating and votes are rounded down to the steps of the client's filter
// sliders, so "at least X" on a step gives the same pool as the exact numbers.
// A slider step changed in the app has to change here too; the steps ride in
// the index so the app can take them from there.
export const INDEX_STEPS = { rating: 0.5, votes: 100, votesCap: 5000 };

const VERSION_KEY = "catalogIndexVersion";
const DIRTY_KEY = "catalogIndexDirty";
const VERSION_CACHE_MS = 60 * 1000;
// Old versions are kept a while for phones that read the header just before
// a rebuild and download a moment after.
const OLD_VERSION_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

let cachedVersion = { value: null, readAt: 0 };

export function stepDown(value, step) {
    const steps = Math.floor(Math.round((value / step) * 1e6) / 1e6);
    return Math.round(steps * step * 1e6) / 1e6;
}

export async function currentIndexVersion(env, { now = Date.now() } = {}) {
    if (now - cachedVersion.readAt < VERSION_CACHE_MS) return cachedVersion.value;
    const row = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(VERSION_KEY).first();
    cachedVersion = { value: row?.value ?? null, readAt: now };
    return cachedVersion.value;
}

export function forgetCachedIndexVersion() {
    cachedVersion = { value: null, readAt: 0 };
}

// Anything that changes what the index would say flags it, and the next
// scheduled run rebuilds. Cheaper than rebuilding on every curation write.
export function markIndexDirtyStatement(env) {
    return env.DB.prepare("INSERT INTO app_config (key, value) VALUES (?, '1') ON CONFLICT (key) DO UPDATE SET value = '1'")
        .bind(DIRTY_KEY);
}

export async function markIndexDirty(env) {
    await markIndexDirtyStatement(env).run();
}

export async function buildIndexBody(env) {
    const items = await env.DB.prepare(
        `SELECT key, media_type, release_year, original_language, vote_average, vote_count
         FROM media_items WHERE published = 1 ORDER BY key`
    ).all();
    const genres = await env.DB.prepare(
        `SELECT g.media_key, g.genre_id FROM media_genres g
         JOIN media_items m ON m.key = g.media_key
         WHERE m.published = 1 ORDER BY g.media_key, g.genre_id`
    ).all();

    const byKey = new Map();
    for (const row of genres.results) {
        if (!byKey.has(row.media_key)) byKey.set(row.media_key, []);
        byKey.get(row.media_key).push(row.genre_id);
    }

    return JSON.stringify({
        format: 1,
        steps: INDEX_STEPS,
        items: items.results.map((row) => ({
            key: row.key,
            type: row.media_type,
            year: row.release_year,
            language: row.original_language,
            genres: byKey.get(row.key) || [],
            rating: stepDown(row.vote_average ?? 0, INDEX_STEPS.rating),
            votes: Math.min(INDEX_STEPS.votesCap, stepDown(row.vote_count ?? 0, INDEX_STEPS.votes))
        }))
    });
}

// The row first, the version second: a phone that sees the new version must
// find its body.
export async function rebuildIndex(env, { now = Date.now() } = {}) {
    const body = await buildIndexBody(env);
    const version = `v1-${(await sha256Hex(body)).slice(0, 16)}`;
    const current = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(VERSION_KEY).first();

    if (current?.value !== version) {
        await env.DB.prepare("INSERT OR IGNORE INTO catalog_index (version, body, created_at) VALUES (?, ?, ?)")
            .bind(version, body, now)
            .run();
        await env.DB.prepare(
            "INSERT INTO app_config (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value"
        ).bind(VERSION_KEY, version).run();
    }

    await env.DB.batch([
        env.DB.prepare("DELETE FROM app_config WHERE key = ?").bind(DIRTY_KEY),
        env.DB.prepare("DELETE FROM catalog_index WHERE version != ? AND created_at < ?")
            .bind(version, now - OLD_VERSION_RETENTION_MS)
    ]);

    forgetCachedIndexVersion();
    return { version, changed: current?.value !== version };
}

export async function rebuildIndexIfDirty(env) {
    const dirty = await env.DB.prepare("SELECT 1 AS yes FROM app_config WHERE key = ?").bind(DIRTY_KEY).first();
    const version = await env.DB.prepare("SELECT value FROM app_config WHERE key = ?").bind(VERSION_KEY).first();
    if (!dirty && version) return null;
    return rebuildIndex(env);
}

export async function loadIndex(env, version = null) {
    const wanted = version ?? (await currentIndexVersion(env));
    if (!wanted) return null;
    return env.DB.prepare("SELECT version, body FROM catalog_index WHERE version = ?").bind(wanted).first();
}
