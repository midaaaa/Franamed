// Writing a moderator's verdicts on a title, all or just what changed since the
// last save. Grouped by the change they make: 170 frames cost one statement per
// (status, tier) pair, against D1's limit of 50 queries per invocation.

import { badRequest } from "./http.js";
import { readConfig } from "./config.js";
import { DIFFICULTY_TIERS, refreshMediaCounters } from "./media.js";

export const MAX_BULK_VERDICTS = 300;

// Ids per UPDATE, leaving room for the other bindings under D1's 100.
const VERDICT_CHUNK = 90;

export function parseVerdicts(raw) {
    const list = Array.isArray(raw) ? raw : [];
    if (list.length > MAX_BULK_VERDICTS) throw badRequest(`At most ${MAX_BULK_VERDICTS} frames per request`);

    const seen = new Set();
    return list.map((verdict) => {
        const imageId = Number.parseInt(verdict.imageId, 10);
        if (!Number.isInteger(imageId)) throw badRequest("Each verdict needs an integer imageId");
        if (seen.has(imageId)) throw badRequest(`Duplicate verdict for image ${imageId}`);
        seen.add(imageId);

        // "pending" takes a frame back to unjudged — how an undo reaches a
        // verdict that was already saved.
        if (!["approved", "rejected", "pending"].includes(verdict.status)) {
            throw badRequest('Each verdict status must be "approved", "rejected" or "pending"');
        }

        const tier = verdict.difficultyTier;
        if (tier !== undefined && tier !== null && !DIFFICULTY_TIERS.includes(tier)) {
            throw badRequest(`difficultyTier must be null or one of: ${DIFFICULTY_TIERS.join(", ")}`);
        }

        return { imageId, status: verdict.status, difficultyTier: tier };
    });
}

export async function applyVerdicts(env, { mediaKey, verdicts, rejectRemaining, moderatorUid, now = Date.now() }) {
    const statements = [];

    // "Everything I did not tick is out". Written first and without naming the
    // ticked frames: the verdicts below overwrite their own rows in the same
    // batch, and a NOT IN list would run past D1's 100 bound parameters.
    if (rejectRemaining) {
        statements.push(
            env.DB.prepare(
                `UPDATE media_images
                 SET status = 'rejected', moderator_status = 'rejected', moderator_uid = ?, moderator_at = ?
                 WHERE media_key = ? AND moderator_status IS NULL`
            ).bind(moderatorUid, now, mediaKey)
        );
    }

    const groups = new Map();
    for (const { imageId, status, difficultyTier } of verdicts) {
        const groupKey = `${status}|${difficultyTier === undefined ? "keep" : difficultyTier}`;
        if (!groups.has(groupKey)) groups.set(groupKey, { status, tier: difficultyTier, ids: [] });
        groups.get(groupKey).ids.push(imageId);
    }

    // An unjudged frame's status is back to what its live reports say.
    const autoHide = [...groups.keys()].some((key) => key.startsWith("pending|"))
        ? (await readConfig(env)).autoHideReportWeight
        : null;

    for (const { status, tier, ids } of groups.values()) {
        for (let start = 0; start < ids.length; start += VERDICT_CHUNK) {
            const chunk = ids.slice(start, start + VERDICT_CHUNK);
            const placeholders = chunk.map(() => "?").join(", ");
            const tierClause = tier === undefined ? "" : ", difficulty_tier = ?";
            const tierBinding = tier === undefined ? [] : [tier];

            // A locked frame's status is its lock, so both can be written in the
            // same statement instead of recomputed afterwards.
            const statement = status === "pending"
                ? env.DB.prepare(
                    `UPDATE media_images
                     SET status = CASE WHEN report_weight >= ? THEN 'rejected' ELSE 'pending' END,
                         moderator_status = NULL, moderator_uid = NULL, moderator_at = NULL${tierClause}
                     WHERE media_key = ? AND id IN (${placeholders})`
                ).bind(autoHide, ...tierBinding, mediaKey, ...chunk)
                : env.DB.prepare(
                    `UPDATE media_images
                     SET status = ?, moderator_status = ?, moderator_uid = ?, moderator_at = ?${tierClause}
                     WHERE media_key = ? AND id IN (${placeholders})`
                ).bind(status, status, moderatorUid, now, ...tierBinding, mediaKey, ...chunk);

            statements.push(statement);
        }
    }

    if (statements.length) await env.DB.batch(statements);
    await refreshMediaCounters(env, mediaKey);

    return { applied: verdicts.length };
}
