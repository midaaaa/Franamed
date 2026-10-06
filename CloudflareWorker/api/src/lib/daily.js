// The daily puzzle, the streak it feeds, and the attempt economy on top.
//
// Days are counted in UTC. The whole point of the daily is that everyone is
// solving the same thing at the same time, which only holds if "today" means
// the same thing in every timezone.

import { badRequest } from "./http.js";
import { readConfig } from "./config.js";
import { seededRandom, selectRoundFrames, selectSpareFrames } from "./frames.js";
import { isPlayableFrame } from "./media.js";

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
export function hashString(value) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < value.length; i += 1) {
        hash ^= value.charCodeAt(i);
        hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash;
}

export const DEFAULT_DAILY_FRAME_COUNT = 6;

export async function loadDailyPlan(env, dateString) {
    return env.DB.prepare("SELECT * FROM daily_overrides WHERE date = ?").bind(dateString).first();
}

// Numbered by how many days actually exist up to it, so a gap in the calendar
// leaves no gap in the numbers.
export async function dailyNumber(env, dateString) {
    const row = await env.DB.prepare("SELECT COUNT(*) AS count FROM daily_overrides WHERE date <= ?")
        .bind(dateString)
        .first();
    return row.count;
}

// Picks the frames once and stores them: chosen at request time they would
// differ between players, between reopenings, and after any re-curation. The
// date seeds the generator so a re-freeze lands the same way.
export async function freezeDailyLayout(env, { dateString, mediaKey, frameCount = DEFAULT_DAILY_FRAME_COUNT, salt = "" }) {
    const images = await env.DB.prepare("SELECT * FROM media_images WHERE media_key = ?").bind(mediaKey).all();

    // Both picks share one generator: the spares are part of the layout, and an
    // unseeded pick there would give two players different substitutes.
    const random = seededRandom(hashString(dateString + salt));

    const frames = selectRoundFrames(images.results, frameCount, { random });
    if (!frames.length) throw badRequest("That film has no approved frames to build a day from");

    const spares = selectSpareFrames(images.results, new Set(frames.map((frame) => frame.id)), 3, { random });

    await env.DB.prepare(
        `UPDATE daily_overrides
         SET frame_ids = ?, spare_ids = ?, frame_count = ?, frozen_at = ?, replaced_at = NULL
         WHERE date = ?`
    ).bind(
        JSON.stringify(frames.map((frame) => frame.id)),
        JSON.stringify(spares.map((frame) => frame.id)),
        frames.length,
        Date.now(),
        dateString
    ).run();

    return { frameIds: frames.map((frame) => frame.id), spareIds: spares.map((frame) => frame.id) };
}

// A moderator's own six, in their order. The spares are still picked by the
// rules so a broken frame keeps a stand-in the moderator did not have to choose.
export async function setDailyFrames(env, { dateString, mediaKey, frameIds }) {
    const images = await env.DB.prepare("SELECT * FROM media_images WHERE media_key = ?").bind(mediaKey).all();
    const approved = new Map(images.results.filter(isPlayableFrame).map((image) => [image.id, image]));

    if (new Set(frameIds).size !== frameIds.length) throw badRequest("Each frame may appear once");
    if (!frameIds.every((id) => approved.has(id))) throw badRequest("Every frame must be an approved frame of that film");

    const random = seededRandom(hashString(dateString));
    const spares = selectSpareFrames(images.results, new Set(frameIds), 3, { random });

    await env.DB.prepare(
        `UPDATE daily_overrides
         SET frame_ids = ?, spare_ids = ?, frame_count = ?, frozen_at = ?, replaced_at = NULL
         WHERE date = ?`
    ).bind(JSON.stringify(frameIds), JSON.stringify(spares.map((frame) => frame.id)), frameIds.length, Date.now(), dateString).run();

    return { frameIds, spareIds: spares.map((frame) => frame.id) };
}

// A frame of an unplayed day that went missing from TMDB gives its place to a
// spare, the same for everyone, and the day is flagged for the moderator. A
// played day stays as it was: players have seen it, and the round's spares
// cover the gap on their phones.
export async function replaceMissingDailyFrames(env, mediaKey, images, { now = Date.now() } = {}) {
    const days = await env.DB.prepare(
        "SELECT * FROM daily_overrides WHERE media_key = ? AND date >= ? AND frame_ids IS NOT NULL"
    ).bind(mediaKey, utcDateString(new Date(now))).all();

    const byId = new Map(images.map((image) => [image.id, image]));
    const usable = (id) => byId.has(id) && byId.get(id).missing_at === null;
    let repaired = 0;

    for (const day of days.results) {
        const frameIds = JSON.parse(day.frame_ids);
        const spareIds = JSON.parse(day.spare_ids || "[]");
        if (frameIds.every(usable) && spareIds.every(usable)) continue;

        const played = await env.DB.prepare("SELECT 1 AS yes FROM daily_results WHERE date = ? LIMIT 1").bind(day.date).first();
        if (played) continue;

        const random = seededRandom(hashString(`${day.date}:replace`));
        const stock = spareIds.filter(usable);
        const layout = [];
        for (const id of frameIds) {
            if (usable(id)) {
                layout.push(id);
                continue;
            }
            const next = stock.shift()
                ?? selectSpareFrames(images, new Set([...frameIds, ...spareIds, ...layout]), 1, { random })[0]?.id;
            if (next !== undefined) layout.push(next);
        }

        const spares = selectSpareFrames(images, new Set(layout), 3, { random }).map((image) => image.id);

        await env.DB.prepare(
            "UPDATE daily_overrides SET frame_ids = ?, spare_ids = ?, replaced_at = ? WHERE date = ?"
        ).bind(JSON.stringify(layout), JSON.stringify(spares), now, day.date).run();
        repaired += 1;
    }

    return repaired;
}

// A film for a day nobody chose by hand: published, with a spare frame beyond
// the six, never a day before. Random, so the calendar does not follow the
// catalogue's order. Null when every eligible film has had its day.
export async function pickRandomDailyFilm(env, { minApproved }) {
    const point = Math.random();
    const from = `SELECT m.key FROM media_items m INDEXED BY idx_media_shuffle
                  WHERE m.media_type = 'movie' AND m.published = 1 AND m.approved_images >= ?
                    AND NOT EXISTS (SELECT 1 FROM daily_overrides d WHERE d.media_key = m.key)`;
    const row = await env.DB.prepare(`${from} AND m.shuffle_key >= ? ORDER BY m.shuffle_key LIMIT 1`)
        .bind(minApproved, point).first()
        ?? await env.DB.prepare(`${from} AND m.shuffle_key < ? ORDER BY m.shuffle_key LIMIT 1`)
            .bind(minApproved, point).first();
    return row?.key ?? null;
}

// With `autoDaily` on, tomorrow gets a random film if nobody scheduled one.
// Only tomorrow: a day that is already running is never filled behind a
// moderator's back. A moderator can still replace the pick before it plays.
export async function autoScheduleTomorrow(env, { now = Date.now() } = {}) {
    const config = await readConfig(env);
    if (!config.autoDaily) return null;

    const date = utcDateString(new Date(now + 24 * 60 * 60 * 1000));
    if (await loadDailyPlan(env, date)) return null;

    const mediaKey = await pickRandomDailyFilm(env, { minApproved: config.targetApprovedFrames });
    if (!mediaKey) {
        console.error("No film left for an automatic daily", date);
        return null;
    }

    const inserted = await env.DB.prepare(
        "INSERT OR IGNORE INTO daily_overrides (date, media_key, created_by, created_at) VALUES (?, ?, 'auto', ?)"
    ).bind(date, mediaKey, now).run();
    if (!inserted.meta?.changes) return null;

    await freezeDailyLayout(env, { dateString: date, mediaKey });
    return { date, mediaKey };
}

// Days scheduled before freezing existed are frozen on first play, otherwise
// they would keep being re-rolled.
export async function ensureFrozen(env, plan) {
    if (plan.frame_ids) return plan;

    await freezeDailyLayout(env, {
        dateString: plan.date,
        mediaKey: plan.media_key,
        frameCount: plan.frame_count || DEFAULT_DAILY_FRAME_COUNT
    });

    return loadDailyPlan(env, plan.date);
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
        attemptsRemaining: Math.max(0, free - used) + bonus
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
