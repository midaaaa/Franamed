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
