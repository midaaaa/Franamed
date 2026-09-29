// Today's spend against the Workers Free daily limits, read from Cloudflare's
// GraphQL analytics. The limits are per account, so nothing is filtered to
// this worker or this database.

import { APIError } from "./http.js";

const GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql";

export const FREE_LIMITS = {
    requests: 100_000,
    rowsRead: 5_000_000,
    rowsWritten: 100_000
};

const QUERY = `query Usage($account: string!, $date: Date!, $start: Time!, $end: Time!) {
  viewer {
    accounts(filter: { accountTag: $account }) {
      workers: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $start, datetime_leq: $end }) {
        sum { requests errors subrequests }
      }
      d1: d1AnalyticsAdaptiveGroups(limit: 10000, filter: { date_geq: $date, date_leq: $date }) {
        sum { readQueries writeQueries rowsRead rowsWritten }
      }
    }
  }
}`;

// Per isolate, so different locations may each ask once a minute. Cache API
// is not an option on workers.dev, and D1 is the budget being measured.
const CACHE_MS = 60_000;
let cached = null;

function total(groups, field) {
    return (groups || []).reduce((sum, group) => sum + (group.sum?.[field] || 0), 0);
}

export async function readUsage(env, now = Date.now()) {
    if (cached && now - cached.fetchedAt < CACHE_MS) return cached;

    if (!env.CF_ANALYTICS_TOKEN || !env.CF_ACCOUNT_ID) {
        throw new APIError(503, "usage_unavailable", "CF_ANALYTICS_TOKEN or CF_ACCOUNT_ID is not set");
    }

    const dayStart = new Date(now);
    dayStart.setUTCHours(0, 0, 0, 0);
    const date = dayStart.toISOString().slice(0, 10);

    const response = await fetch(GRAPHQL_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${env.CF_ANALYTICS_TOKEN}`, "Content-Type": "application/json" },
        body: JSON.stringify({
            query: QUERY,
            variables: { account: env.CF_ACCOUNT_ID, date, start: dayStart.toISOString(), end: new Date(now).toISOString() }
        })
    });
    if (!response.ok) {
        throw new APIError(502, "analytics_error", `Cloudflare analytics responded with ${response.status}`);
    }

    const body = await response.json();
    if (body.errors?.length) {
        throw new APIError(502, "analytics_error", body.errors[0].message || "Cloudflare analytics refused the query");
    }

    const account = body.data?.viewer?.accounts?.[0];
    if (!account) throw new APIError(502, "analytics_error", "No analytics for this account");

    cached = {
        date,
        fetchedAt: now,
        resetsAt: dayStart.getTime() + 86_400_000,
        workers: {
            requests: total(account.workers, "requests"),
            errors: total(account.workers, "errors"),
            subrequests: total(account.workers, "subrequests")
        },
        d1: {
            rowsRead: total(account.d1, "rowsRead"),
            rowsWritten: total(account.d1, "rowsWritten"),
            readQueries: total(account.d1, "readQueries"),
            writeQueries: total(account.d1, "writeQueries")
        },
        limits: FREE_LIMITS
    };
    return cached;
}

export function resetUsageCache() {
    cached = null;
}
