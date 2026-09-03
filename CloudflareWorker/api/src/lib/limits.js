// Rate limiting.
//
// Two honest limitations of the Workers rate limiter shape how it is used here:
// counters are per Cloudflare location rather than global, and the only windows
// available are 10 and 60 seconds. That makes it a good defence against bursts
// and a poor one against slow drip — someone creating a thousand accounts one
// per minute over a day sails straight through.
//
// So this is deliberately only half the answer. The other half is that a brand
// new account's vote carries no weight until it has actually played (see
// `voterWeight`), which attacks the economics rather than the request rate:
// minting accounts is cheap, playing rounds on each of them is not.

import { tooManyRequests } from "./http.js";
import { readConfig } from "./config.js";

/// Falls open when the binding is missing so a misconfigured deploy degrades
/// into an unprotected service rather than a dead one.
async function check(limiter, key) {
    if (!limiter) return true;
    const { success } = await limiter.limit({ key });
    return success;
}

export async function limitByIP(env, request, name) {
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    if (!(await check(env[name], `${name}:${ip}`))) {
        throw tooManyRequests("Слишком много запросов, попробуйте через минуту");
    }
}

export async function limitByUser(env, uid, name) {
    if (!(await check(env[name], `${name}:${uid}`))) {
        throw tooManyRequests("Слишком много запросов, попробуйте через минуту");
    }
}

// How much a user's judgement counts.
//
// `report_multiplier` is the admin's dial on an individual. On top of it, an
// account that has not played yet counts for nothing at all: weighted voting
// assumes accounts are scarce, and anonymous accounts are free, so without this
// a hundred throwaway sign-ins could swing any frame.
export async function voterWeight(env, user) {
    const config = await readConfig(env);
    if (config.voteWeightMinRounds <= 0) return user.report_multiplier;

    const played = await env.DB.prepare("SELECT COUNT(*) AS count FROM watched_media WHERE uid = ?")
        .bind(user.uid)
        .first();

    return played.count >= config.voteWeightMinRounds ? user.report_multiplier : 0;
}

export async function roundsPlayed(env, uid) {
    const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM watched_media WHERE uid = ?").bind(uid).first();
    return row.count;
}
