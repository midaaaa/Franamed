// What runs on the cron trigger. Each step is bounded so one run stays under
// the 50 external and 50 D1 queries a free invocation gets.

import { rebuildIndexIfDirty } from "./catalogIndex.js";
import { backfillRatings } from "./tmdb.js";

export async function runScheduled(env) {
    const steps = [
        ["ratings", () => backfillRatings(env)],
        ["index", () => rebuildIndexIfDirty(env)]
    ];

    for (const [name, step] of steps) {
        try {
            const outcome = await step();
            if (outcome) console.log(`scheduled ${name}`, JSON.stringify(outcome));
        } catch (error) {
            console.error(`scheduled ${name} failed`, error?.stack || error);
        }
    }
}
