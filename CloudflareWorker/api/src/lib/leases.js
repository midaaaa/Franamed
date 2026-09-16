// Leasing a title to one curator at a time. Reviewing a batch writes the same
// frames as curating it, so every way in takes the same lock. A curator's work
// is local, so the expiry runs on heartbeats rather than on requests.

import { roleRank } from "./auth.js";

export function serializeLease(row, { now = Date.now(), windowMs, uid = null } = {}) {
    if (!row) return null;
    return {
        mediaKey: row.media_key,
        uid: row.uid,
        displayName: row.display_name ?? null,
        role: row.role,
        acquiredAt: row.acquired_at,
        lastActivityAt: row.touched_at,
        expiresAt: row.touched_at + windowMs,
        secondsSinceActivity: Math.max(0, Math.round((now - row.touched_at) / 1000)),
        isMine: uid !== null && row.uid === uid
    };
}

export async function loadLease(env, mediaKey) {
    return env.DB.prepare(
        `SELECT l.*, u.display_name
         FROM title_leases l LEFT JOIN users u ON u.uid = l.uid
         WHERE l.media_key = ?`
    ).bind(mediaKey).first();
}

export function isLive(row, { now = Date.now(), windowMs }) {
    return Boolean(row) && row.released_at === null && row.touched_at > now - windowMs;
}

// One conditional upsert, so two curators arriving at once cannot both win it.
export async function acquireLease(env, user, mediaKey, { now = Date.now(), windowMs } = {}) {
    const row = await env.DB.prepare(
        `INSERT INTO title_leases (media_key, uid, role, acquired_at, touched_at, released_at)
         VALUES (?1, ?2, ?3, ?4, ?4, NULL)
         ON CONFLICT (media_key) DO UPDATE
            SET uid = excluded.uid,
                role = excluded.role,
                acquired_at = CASE
                    WHEN title_leases.uid = excluded.uid AND title_leases.released_at IS NULL
                    THEN title_leases.acquired_at ELSE excluded.acquired_at END,
                touched_at = excluded.touched_at,
                released_at = NULL
          WHERE title_leases.released_at IS NOT NULL
             OR title_leases.uid = excluded.uid
             OR title_leases.touched_at <= ?5
         RETURNING *`
    ).bind(mediaKey, user.uid, user.role, now, now - windowMs).first();

    return row || null;
}

// Seniority only, never equal rank. An admin's own lease still expires on the
// timer, or a title they forgot would stay locked for good.
export function canTakeOver(user, holder) {
    return roleRank(user.role) > roleRank(holder.role);
}

export async function takeOverLease(env, user, holder, mediaKey, { reason = null, now = Date.now() } = {}) {
    const row = await env.DB.prepare(
        `UPDATE title_leases
            SET uid = ?, role = ?, acquired_at = ?, touched_at = ?, released_at = NULL
          WHERE media_key = ? AND uid = ? AND released_at IS NULL
          RETURNING *`
    ).bind(user.uid, user.role, now, now, mediaKey, holder.uid).first();

    if (!row) return null;

    await env.DB.prepare(
        `INSERT INTO lease_notices (uid, media_key, taken_by, taken_role, reason, created_at)
         VALUES (?, ?, ?, ?, ?, ?)`
    ).bind(holder.uid, mediaKey, user.uid, user.role, reason ? String(reason).slice(0, 200) : null, now).run();

    return row;
}

// Never revives an expired lease: the draft on the device is only valid while
// the lease is.
export async function touchLease(env, user, mediaKey, { now = Date.now(), windowMs } = {}) {
    return env.DB.prepare(
        `UPDATE title_leases SET touched_at = ?
          WHERE media_key = ? AND uid = ? AND released_at IS NULL AND touched_at > ?
          RETURNING *`
    ).bind(now, mediaKey, user.uid, now - windowMs).first();
}

export async function releaseLease(env, user, mediaKey, { now = Date.now() } = {}) {
    return env.DB.prepare(
        `UPDATE title_leases SET released_at = ?
          WHERE media_key = ? AND uid = ? AND released_at IS NULL
          RETURNING *`
    ).bind(now, mediaKey, user.uid).first();
}

export async function takeNotices(env, uid, { now = Date.now(), limit = 20 } = {}) {
    const rows = await env.DB.prepare(
        `SELECT n.*, u.display_name AS taken_by_name
         FROM lease_notices n LEFT JOIN users u ON u.uid = n.taken_by
         WHERE n.uid = ? AND n.delivered_at IS NULL
         ORDER BY n.created_at DESC LIMIT ?`
    ).bind(uid, limit).all();

    if (rows.results.length) {
        await env.DB.prepare("UPDATE lease_notices SET delivered_at = ? WHERE uid = ? AND delivered_at IS NULL")
            .bind(now, uid)
            .run();
    }

    return rows.results.map((row) => ({
        mediaKey: row.media_key,
        takenBy: row.taken_by,
        takenByName: row.taken_by_name ?? null,
        takenByRole: row.taken_role,
        reason: row.reason,
        createdAt: row.created_at
    }));
}
