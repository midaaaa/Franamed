// A player's progress through a playlist: read by the playlist screens,
// written by the finished-round record.

// Progress rows are matched against the playlist's *current* playable contents
// rather than pruned when a curator edits the list or a title leaves the game.
// A title removed and later put back keeps the progress it had, and nothing has
// to be cleaned up on edit. The catalogue side and the player side are read
// separately and matched here, so players can move to a database of their own.
export async function progressSummary(env, uid, playlistId) {
    const [playable, progress] = await env.DB.batch([
        env.DB.prepare(
            `SELECT pi.media_key FROM playlist_items pi
             JOIN media_items m ON m.key = pi.media_key
             WHERE pi.playlist_id = ? AND m.published = 1`
        ).bind(playlistId),
        env.DB.prepare(
            "SELECT media_key, was_correct FROM playlist_progress WHERE uid = ? AND playlist_id = ? AND state = 'completed'"
        ).bind(uid, playlistId)
    ]);

    const keys = new Set(playable.results.map((item) => item.media_key));
    const answeredRows = progress.results.filter((item) => keys.has(item.media_key));
    const row = {
        total: keys.size,
        answered: answeredRows.length,
        correct: answeredRows.filter((item) => item.was_correct === 1).length
    };

    const completion = await env.DB.prepare(
        "SELECT times_completed, completed_at FROM playlist_completions WHERE uid = ? AND playlist_id = ?"
    ).bind(uid, playlistId).first();

    return {
        total: row.total,
        answered: row.answered,
        correct: row.correct,
        accuracy: row.answered > 0 ? row.correct / row.answered : null,
        timesCompleted: completion?.times_completed ?? 0,
        completedAt: completion?.completed_at ?? null
    };
}

// Retrying overwrites the single record for that title; no history is kept,
// which is what makes "replay the ones I got wrong" simple.
export async function recordPlaylistAnswer(env, user, playlistId, { mediaKey, attemptsUsed, wasCorrect }) {
    await env.DB.prepare(
        `INSERT INTO playlist_progress (uid, playlist_id, media_key, state, attempts_used, was_correct, updated_at)
         VALUES (?, ?, ?, 'completed', ?, ?, ?)
         ON CONFLICT (uid, playlist_id, media_key) DO UPDATE SET
            state = 'completed', attempts_used = excluded.attempts_used,
            was_correct = excluded.was_correct, updated_at = excluded.updated_at`
    ).bind(user.uid, playlistId, mediaKey, attemptsUsed, wasCorrect ? 1 : 0, Date.now()).run();

    const summary = await progressSummary(env, user.uid, playlistId);
    if (summary.total > 0 && summary.answered >= summary.total && summary.completedAt === null) {
        await env.DB.prepare(
            `INSERT INTO playlist_completions (uid, playlist_id, times_completed, completed_at)
             VALUES (?, ?, 1, ?)
             ON CONFLICT (uid, playlist_id) DO UPDATE SET completed_at = excluded.completed_at`
        ).bind(user.uid, playlistId, Date.now()).run();
    }

    return { progress: await progressSummary(env, user.uid, playlistId) };
}

// ------------------------------------------------------------------ folder

// The shelf shows a playlist as a folder with up to three posters, cover first.
// The server picks them once, at publishing, and keeps them until the curator
// changes them or one of them leaves the list; it never reshuffles on its own.
export const MAX_FOLDER_POSTERS = 3;

export function parseFolderKeys(row) {
    try {
        const keys = JSON.parse(row.folder_keys || "[]");
        return Array.isArray(keys) ? keys.filter((key) => typeof key === "string") : [];
    } catch {
        return [];
    }
}

async function membersWithPosters(env, playlistId) {
    const rows = await env.DB.prepare(
        `SELECT pi.media_key, m.poster_url FROM playlist_items pi
         JOIN media_items m ON m.key = pi.media_key
         WHERE pi.playlist_id = ? AND m.poster_url IS NOT NULL`
    ).bind(playlistId).all();
    return new Map(rows.results.map((row) => [row.media_key, row.poster_url]));
}

function pickRandom(keys, count) {
    const pool = [...keys];
    const picked = [];
    while (pool.length > 0 && picked.length < count) {
        picked.push(pool.splice(Math.floor(Math.random() * pool.length), 1)[0]);
    }
    return picked;
}

// Keeps the stored folder valid against the current contents. A curator's
// choice loses only the titles that left; an automatic one, or a curator's
// choice left empty, is picked again from scratch.
export async function refreshFolder(env, playlistId, { force = false } = {}) {
    const row = await env.DB.prepare("SELECT folder_keys, folder_auto, published FROM playlists WHERE id = ?")
        .bind(playlistId).first();
    if (!row) return;

    const posters = await membersWithPosters(env, playlistId);
    const stored = parseFolderKeys(row);
    let keys = stored.filter((key) => posters.has(key));
    let auto = row.folder_auto === 1;

    const brokenAuto = auto && keys.length !== stored.length;
    if (force || keys.length === 0 || brokenAuto) {
        keys = row.published === 1 || force ? pickRandom(posters.keys(), MAX_FOLDER_POSTERS) : [];
        auto = true;
    }

    const next = keys.length > 0 ? JSON.stringify(keys) : null;
    if (next !== (row.folder_keys ?? null) || (auto ? 1 : 0) !== row.folder_auto) {
        await env.DB.prepare("UPDATE playlists SET folder_keys = ?, folder_auto = ? WHERE id = ?")
            .bind(next, auto ? 1 : 0, playlistId).run();
    }
}

export async function folderPosters(env, row) {
    const keys = parseFolderKeys(row);
    if (keys.length === 0) return row.cover_image_url ? [row.cover_image_url] : [];
    const posters = await membersWithPosters(env, row.id);
    return keys.map((key) => posters.get(key)).filter(Boolean);
}

// ------------------------------------------------------------------ order

// Without the curator's order every player walks the list in an order of
// their own that stays put between sessions: a stable hash of who and what.
export function playerOrderRank(uid, playlistId, mediaKey) {
    let hash = 2166136261;
    for (const char of `${uid}:${playlistId}:${mediaKey}`) {
        hash ^= char.codePointAt(0);
        hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash;
}
