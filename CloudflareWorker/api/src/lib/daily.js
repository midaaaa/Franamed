// The daily puzzle, the streak it feeds, and the attempt economy on top.
//
// Days are counted in UTC. The whole point of the daily is that everyone is
// solving the same thing at the same time, which only holds if "today" means
// the same thing in every timezone.

import { notFound } from "./http.js";
import { readConfig } from "./config.js";

export function utcDateString(date = new Date()) {
    return date.toISOString().slice(0, 10);
}

export function previousDateString(dateString) {
    const date = new Date(`${dateString}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() - 1);
    return utcDateString(date);
}

export function isValidDateString(value) {
    return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

// FNV-1a. Any stable hash works here; this one is short and has no dependencies.
function hashString(value) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < value.length; i += 1) {
        hash ^= value.charCodeAt(i);
        hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash;
}

// Priority is a hand-scheduled override, then a deterministic pick from the
// approved pool. The deterministic pick is written back as an override so the
// answer for a given date never changes once anyone has seen it — without that,
// growing the catalogue would silently rewrite history.
export async function resolveDailyMediaKey(env, dateString) {
    const override = await env.DB.prepare("SELECT media_key FROM daily_overrides WHERE date = ?")
        .bind(dateString)
        .first();
    if (override) return override.media_key;

    // Movies only, permanently. A show's backdrop stands in for the whole
    // series, so a random still risks spoiling a season the player has not
    // reached — a problem a film simply does not have.
    const pool = await env.DB.prepare(
        `SELECT key FROM media_items
         WHERE media_type = 'movie' AND status = 'approved' AND approved_images >= 6
         ORDER BY key`
    ).all();

    if (!pool.results.length) throw notFound("No approved movie is available for the daily puzzle");

    const chosen = pool.results[hashString(dateString) % pool.results.length].key;

    await env.DB.prepare(
        "INSERT OR IGNORE INTO daily_overrides (date, media_key, created_by, created_at) VALUES (?, ?, 'system', ?)"
    ).bind(dateString, chosen, Date.now()).run();

    return chosen;
}

// ------------------------------------------------------------ attempt budget

export async function refreshAttemptBudget(env, user) {
    const today = utcDateString();
    if (user.last_attempt_reset_date === today) return user;

    await env.DB.prepare(
        "UPDATE users SET attempts_used_today = 0, last_attempt_reset_date = ? WHERE uid = ?"
    ).bind(today, user.uid).run();

    return { ...user, attempts_used_today: 0, last_attempt_reset_date: today };
}

export async function attemptBudget(env, user) {
    const config = await readConfig(env);
    const refreshed = await refreshAttemptBudget(env, user);

    const free = config.dailyFreeAttempts;
    const bonus = refreshed.bonus_attempts_available;
    const used = refreshed.attempts_used_today;

    return {
        freeAttempts: free,
        bonusAttempts: bonus,
        attemptsUsedToday: used,
        attemptsRemaining: Math.max(0, free - used) + bonus,
        gateEnabled: config.curationGateEnabled
    };
}

export async function grantBonusAttempts(env, uid, amount) {
    if (amount <= 0) return;
    await env.DB.prepare("UPDATE users SET bonus_attempts_available = bonus_attempts_available + ? WHERE uid = ?")
        .bind(amount, uid)
        .run();
}

// Free attempts are spent before bonus ones, so a reward earned by curating is
// not quietly burned while the daily allowance still had room.
export async function consumeAttempt(env, user) {
    const config = await readConfig(env);
    const refreshed = await refreshAttemptBudget(env, user);

    if (refreshed.attempts_used_today < config.dailyFreeAttempts) {
        await env.DB.prepare("UPDATE users SET attempts_used_today = attempts_used_today + 1 WHERE uid = ?")
            .bind(user.uid)
            .run();
        return true;
    }

    if (refreshed.bonus_attempts_available > 0) {
        await env.DB.prepare("UPDATE users SET bonus_attempts_available = bonus_attempts_available - 1 WHERE uid = ?")
            .bind(user.uid)
            .run();
        return true;
    }

    return false;
}

// -------------------------------------------------------------------- streak

// A streak counts solved dailies, not attempted ones — the same rule Wordle
// uses. Playing and failing ends it; skipping a day ends it too.
export function nextStreak(user, dateString, wasCorrect) {
    if (!wasCorrect) return { dailyStreak: 0, longestStreak: user.longest_streak };

    const continues = user.last_daily_completed_date === previousDateString(dateString);
    const alreadyCountedToday = user.last_daily_completed_date === dateString;

    const dailyStreak = alreadyCountedToday ? user.daily_streak : continues ? user.daily_streak + 1 : 1;

    return { dailyStreak, longestStreak: Math.max(user.longest_streak, dailyStreak) };
}

export async function recordDailyResult(env, user, { dateString, mediaKey, wasCorrect, attemptsUsed }) {
    const config = await readConfig(env);
    const existing = await env.DB.prepare("SELECT date FROM daily_results WHERE uid = ? AND date = ?")
        .bind(user.uid, dateString)
        .first();

    const { dailyStreak, longestStreak } = nextStreak(user, dateString, wasCorrect);

    await env.DB.prepare(
        `INSERT INTO daily_results (uid, date, media_key, was_correct, attempts_used, completed_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT (uid, date) DO NOTHING`
    ).bind(user.uid, dateString, mediaKey, wasCorrect ? 1 : 0, attemptsUsed, Date.now()).run();

    // Replaying an already-recorded day must not pay out a second time.
    if (existing) return { dailyStreak: user.daily_streak, longestStreak: user.longest_streak, awardedAttempts: 0 };

    const awardedAttempts = wasCorrect ? config.attemptsPerCorrectStreak : 0;

    await env.DB.prepare(
        `UPDATE users
         SET daily_streak = ?, longest_streak = ?, last_daily_completed_date = ?,
             bonus_attempts_available = bonus_attempts_available + ?
         WHERE uid = ?`
    ).bind(dailyStreak, longestStreak, wasCorrect ? dateString : user.last_daily_completed_date, awardedAttempts, user.uid).run();

    return { dailyStreak, longestStreak, awardedAttempts };
}
