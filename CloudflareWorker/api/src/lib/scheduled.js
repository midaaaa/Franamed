// What runs on the cron triggers. Each step is bounded so one run stays under
// the 50 D1 queries and 50 outside requests a free invocation gets, and the
// steps go cheapest and most important first in case a run falls short. What
// the sync changes reaches the index on the next run.

import { pruneRefreshTokens } from "./auth.js";
import { rebuildIndexIfDirty } from "./catalogIndex.js";
import { autoScheduleTomorrow } from "./daily.js";
import { syncDueTitles } from "./sync.js";
import { backfillRatings } from "./tmdb.js";

export const NIGHTLY_CRON = "17 3 * * *";

export async function runScheduled(env, event = {}) {
    if (event.cron === NIGHTLY_CRON) {
        await step("tokens", () => pruneRefreshTokens(env));
        return;
    }

    await step("daily", () => autoScheduleTomorrow(env));
    await step("index", () => rebuildIndexIfDirty(env));
    // Both spend most of a run's queries, so a run does one or the other.
    const backfilled = await step("ratings", () => backfillRatings(env));
    if (!backfilled) await step("sync", () => syncDueTitles(env));
}

async function step(name, work) {
    try {
        const outcome = await work();
        if (outcome) console.log(`scheduled ${name}`, JSON.stringify(outcome));
        return outcome;
    } catch (error) {
        console.error(`scheduled ${name} failed`, error?.stack || error);
        return null;
    }
}
