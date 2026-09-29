// Deleting an account, from the player's own profile or by an admin.

import { conflict } from "./http.js";
import { readConfig } from "./config.js";
import { recomputeTitleImageStatuses } from "./media.js";

// A worker invocation gets 50 D1 queries and a recompute spends four, so a
// prolific reporter's remaining titles settle on their next curation write.
const DELETION_RECOMPUTE_LIMIT = 10;

export async function deleteAccount(env, target) {
    if (target.role === "admin") {
        const others = await env.DB.prepare("SELECT COUNT(*) AS count FROM users WHERE role = 'admin' AND uid != ?")
            .bind(target.uid)
            .first();
        if (others.count === 0) throw conflict("The last admin cannot be deleted");
    }

    // Their reports stop counting, so the frames they hid are re-derived.
    const reported = await env.DB.prepare(
        `SELECT DISTINCT i.media_key FROM image_reports r JOIN media_images i ON i.id = r.image_id
         WHERE r.uid = ? AND r.dismissed_at IS NULL`
    ).bind(target.uid).all();

    // Everything keyed to the account goes with it by cascade.
    await env.DB.prepare("DELETE FROM users WHERE uid = ?").bind(target.uid).run();

    const config = await readConfig(env);
    for (const row of reported.results.slice(0, DELETION_RECOMPUTE_LIMIT)) {
        await recomputeTitleImageStatuses(env, row.media_key, { autoHideReportWeight: config.autoHideReportWeight });
    }
}
