// Writing a whole title's verdicts, shared by direct curation and by applying a
// batch. Grouped by the change they make: 170 frames cost one statement per
// (status, tier) pair, against D1's limit of 50 queries per invocation.

import { badRequest } from "./http.js";
import { DIFFICULTY_TIERS, refreshMediaCounters } from "./media.js";

export const MAX_BULK_VERDICTS = 300;

export function parseVerdicts(raw) {
    const list = Array.isArray(raw) ? raw : [];
    if (list.length > MAX_BULK_VERDICTS) throw badRequest(`At most ${MAX_BULK_VERDICTS} frames per request`);

    const seen = new Set();
    return list.map((verdict) => {
        const imageId = Number.parseInt(verdict.imageId, 10);
        if (!Number.isInteger(imageId)) throw badRequest("Each verdict needs an integer imageId");
        if (seen.has(imageId)) throw badRequest(`Duplicate verdict for image ${imageId}`);
        seen.add(imageId);

        // Clearing a lock has to consult the votes again, which is a per-frame
        // job — the single-frame endpoint handles it.
        if (!["approved", "rejected"].includes(verdict.status)) {
            throw badRequest('Each verdict status must be "approved" or "rejected"');
        }

        const tier = verdict.difficultyTier;
        if (tier !== undefined && tier !== null && !DIFFICULTY_TIERS.includes(tier)) {
            throw badRequest(`difficultyTier must be null or one of: ${DIFFICULTY_TIERS.join(", ")}`);
        }

        return { imageId, status: verdict.status, difficultyTier: tier };
    });
}

export async function applyVerdicts(env, { mediaKey, verdicts, rejectRemaining, moderatorUid, now = Date.now() }) {
    const groups = new Map();
    for (const { imageId, status, difficultyTier } of verdicts) {
        const groupKey = `${status}|${difficultyTier === undefined ? "keep" : difficultyTier}`;
        if (!groups.has(groupKey)) groups.set(groupKey, { status, tier: difficultyTier, ids: [] });
        groups.get(groupKey).ids.push(imageId);
    }

    const statements = [];
    for (const { status, tier, ids } of groups.values()) {
        const placeholders = ids.map(() => "?").join(", ");
        // A locked frame's status is its lock, so both can be written in the
        // same statement instead of recomputed afterwards.
        const tierClause = tier === undefined ? "" : ", difficulty_tier = ?";
        const bindings = tier === undefined
            ? [status, status, moderatorUid, now, mediaKey, ...ids]
            : [status, status, moderatorUid, now, tier, mediaKey, ...ids];

        statements.push(
            env.DB.prepare(
                `UPDATE media_images
                 SET status = ?, moderator_status = ?, moderator_uid = ?, moderator_at = ?${tierClause}
                 WHERE media_key = ? AND id IN (${placeholders})`
            ).bind(...bindings)
        );
    }

    // "Everything I did not tick is out".
    if (rejectRemaining) {
        const judged = verdicts.map((verdict) => verdict.imageId);
        const exclusion = judged.length ? `AND id NOT IN (${judged.map(() => "?").join(", ")})` : "";

        statements.push(
            env.DB.prepare(
                `UPDATE media_images
                 SET status = 'rejected', moderator_status = 'rejected', moderator_uid = ?, moderator_at = ?
                 WHERE media_key = ? AND moderator_status IS NULL ${exclusion}`
            ).bind(moderatorUid, now, mediaKey, ...judged)
        );
    }

    if (statements.length) await env.DB.batch(statements);
    await refreshMediaCounters(env, mediaKey);

    return { applied: verdicts.length };
}
