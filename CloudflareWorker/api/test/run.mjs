// End-to-end checks of the real worker (src/index.js) against an in-memory
// database built from schema.sql. Run from CloudflareWorker/api:
//
//     node --no-warnings test/run.mjs

import { readFileSync } from "node:fs";
import { D1 } from "./d1.mjs";

const API = new URL("..", import.meta.url).pathname;
const SECRET = "test-secret-test-secret-test-secret-00";

const { default: worker } = await import(`${API}src/index.js`);
const { signJWT } = await import(`${API}src/lib/crypto.js`);
const { refreshMediaCounters, buildCatalogQuery } = await import(`${API}src/lib/media.js`);
const { reporterWeight } = await import(`${API}src/lib/limits.js`);

let failures = 0;
function check(label, condition, detail = "") {
    if (condition) {
        console.log(`  ok   ${label}`);
    } else {
        failures += 1;
        console.log(`  FAIL ${label} ${detail}`);
    }
}

// ------------------------------------------------------------------ seed

const db = new D1();
db.exec(readFileSync(`${API}schema.sql`, "utf8"));
const env = { DB: db, JWT_SECRET: SECRET, TMDB_API_KEY: "test" };

const now = Date.now();
for (const [uid, role, name, anonymous] of [
    ["me", "admin", "Вы", 0],
    ["mod", "moderator", "Аня", 0],
    ["cur", "moderator", "Дима", 0],
    ["plain", "user", null, 1]
]) {
    db.db.prepare("INSERT INTO users (uid, role, display_name, is_anonymous, created_at) VALUES (?, ?, ?, ?, ?)")
        .run(uid, role, name, anonymous, now);
}

let nextImage = 1;
function addTitle(key, { title, popularity, poster = "/p.jpg", frames, publishMode = "auto", rejected = false }) {
    const [mediaType, tmdbId] = key.split("_");
    db.db.prepare(
        `INSERT INTO media_items (key, tmdb_id, media_type, title, original_title, popularity, poster_url, status, publish_mode, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(key, Number(tmdbId), mediaType, title, title, popularity, poster, rejected ? "rejected" : "pending", publishMode, now - nextImage);

    nextImage = Math.max(nextImage, (db.db.prepare("SELECT MAX(id) AS id FROM media_images").get().id ?? 0) + 1);
    for (const [verdict, tier] of frames) {
        const id = nextImage++;
        db.db.prepare(
            `INSERT INTO media_images (id, media_key, file_path, status, difficulty_tier, moderator_status, tmdb_vote_average, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
        ).run(id, key, `/${key}-${id}.jpg`, verdict ?? "pending", tier ?? null, verdict, id % 7, now);
    }
}

const judged = (approved, rejected, unjudged, tiers = ["hard", "medium", "easy"]) => [
    ...Array.from({ length: approved }, (_, i) => ["approved", tiers[i % tiers.length]]),
    ...Array.from({ length: rejected }, () => ["rejected", null]),
    ...Array.from({ length: unjudged }, () => [null, null])
];

addTitle("movie_101", { title: "Альфа", popularity: 90, frames: judged(8, 4, 8) });
addTitle("movie_102", { title: "Бета", popularity: 80, frames: judged(12, 0, 0) });
addTitle("movie_103", { title: "Гамма", popularity: 70, poster: null, frames: judged(0, 0, 10) });
addTitle("movie_104", { title: "Дельта", popularity: 60, frames: judged(7, 2, 0) });
addTitle("movie_105", { title: "Эпсилон", popularity: 50, publishMode: "on", frames: judged(6, 0, 9) });
addTitle("movie_106", { title: "Отказ", popularity: 45, rejected: true, frames: judged(6, 0, 0) });
addTitle("tv_201", { title: "Сериал", popularity: 40, frames: judged(0, 0, 8) });

const keys = db.db.prepare("SELECT key FROM media_items ORDER BY key").all().map((row) => row.key);
for (const key of keys) await refreshMediaCounters({ DB: db }, key);

const row = (key) => db.db.prepare("SELECT * FROM media_items WHERE key = ?").get(key);
const movies = keys.filter((key) => key.startsWith("movie_"));

// ------------------------------------------------------------------ transport

const tmdbCalls = [];
const graphqlCalls = [];
globalThis.fetch = async (url, init) => {
    const target = new URL(url);
    if (target.hostname === "api.cloudflare.com") {
        graphqlCalls.push(JSON.parse(init.body));
        return new Response(JSON.stringify({
            data: { viewer: { accounts: [{
                workers: [{ sum: { requests: 1200, errors: 3, subrequests: 40 } }, { sum: { requests: 300, errors: 0, subrequests: 0 } }],
                d1: [{ sum: { readQueries: 900, writeQueries: 50, rowsRead: 250000, rowsWritten: 4000 } }]
            }] } }
        }), { status: 200 });
    }
    tmdbCalls.push(target.pathname + target.search);
    const reply = (body) => new Response(JSON.stringify(body), { status: 200 });

    if (target.pathname.endsWith("/search/multi")) {
        return reply({
            results: [
                { id: 101, media_type: "movie", title: "Альфа", original_title: "Alpha", release_date: "2024-05-01", poster_path: "/a.jpg" },
                { id: 42, media_type: "movie", title: "Новый", original_title: "Fresh", release_date: "2020-01-01", poster_path: "/n.jpg" },
                { id: 7, media_type: "person", name: "Актёр" },
                { id: 693, media_type: "tv", name: "Сериал", original_name: "Show", first_air_date: "2005-01-01", poster_path: null }
            ]
        });
    }
    if (target.pathname.startsWith("/3/discover/") || target.pathname.startsWith("/3/trending/")) {
        return reply({
            page: 1,
            total_pages: 3,
            results: [
                { id: 101, title: "Альфа", original_title: "Alpha", release_date: "2024-05-01", poster_path: "/a.jpg" },
                { id: 4242, title: "Классика", original_title: "Classic", release_date: "1994-01-01", poster_path: "/c.jpg" }
            ]
        });
    }
    if (target.pathname === "/3/movie/4242") {
        return reply({
            id: 4242, title: "Классика", original_title: "Classic", release_date: "1994-01-01", original_language: "en",
            popularity: 80, poster_path: "/default-with-title.jpg", genres: [{ id: 18 }],
            images: {
                posters: [
                    { file_path: "/clean-low.jpg", iso_639_1: null, vote_average: 4.1, vote_count: 3 },
                    { file_path: "/clean-best.jpg", iso_639_1: null, vote_average: 5.6, vote_count: 9 }
                ],
                backdrops: Array.from({ length: 8 }, (_, i) => ({
                    file_path: `/classic${i}.jpg`, iso_639_1: null, vote_average: i, vote_count: i, width: 1920, height: 1080, aspect_ratio: 1.778
                }))
            }
        });
    }
    throw new Error(`unexpected fetch ${url}`);
};

async function call(uid, method, path, body) {
    const token = await signJWT({ sub: uid }, SECRET, 900);
    const request = new Request(`https://api.test${path}`, {
        method,
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: body ? JSON.stringify(body) : undefined
    });
    const response = await worker.fetch(request, env, {});
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null };
}

// ------------------------------------------------------------------ counters and publishing

console.log("counters");
check("every title gets its own shuffle point in [0, 1)",
    db.db.prepare("SELECT COUNT(DISTINCT shuffle_key) AS n, MIN(shuffle_key) AS lo, MAX(shuffle_key) AS hi FROM media_items").get().n === keys.length);
check("counts are derived", row("movie_101").approved_images === 8 && row("movie_101").unjudged_images === 8 && row("movie_101").reviewed_images === 12);
check("auto publishes a finished title", row("movie_102").published === 1 && row("movie_104").published === 1);
check("auto waits while frames are unjudged", row("movie_101").published === 0);
check("'on' publishes early", row("movie_105").published === 1);
check("no poster, no game", row("movie_103").published === 0);
check("a rejected title is never published", row("movie_106").published === 0 && row("movie_106").work_weight === 0);

// ------------------------------------------------------------------ lists

console.log("home and queue");
let res = await call("me", "GET", "/v1/curation/home");
check("home answers with badges", res.status === 200 && res.body.config.publishMinFrames === 6
    && typeof res.body.badges.queue === "number" && !("reviews" in res.body.badges), JSON.stringify(res.body));
const queueBadge = res.body.badges.queue;
res = await call("plain", "GET", "/v1/curation/home");
check("a player is refused", res.status === 403);

res = await call("cur", "GET", "/v1/curation/queue?limit=50");
const queueKeys = res.body.items.map((item) => item.key);
check("badge equals queue size", queueKeys.length === queueBadge, `${queueKeys.length} vs ${queueBadge}`);
check("queue holds only titles with unjudged frames",
    JSON.stringify([...queueKeys].sort()) === JSON.stringify(["movie_101", "movie_103", "movie_105", "tv_201"]), JSON.stringify(queueKeys));
check("started titles come first", queueKeys.slice(0, 2).every((key) => ["movie_101", "movie_105"].includes(key)), JSON.stringify(queueKeys));

console.log("catalog");
res = await call("cur", "GET", "/v1/curation/catalog?mediaType=movie&filter=all&sort=popularity&limit=2");
check("page of 2 with more", res.status === 200 && res.body.items.length === 2 && res.body.hasMore === true);
check("rows carry publishing and presence", res.body.items.every((item) => "published" in item && "publishMode" in item && "workedBy" in item));
const seen = [];
for (let offset = 0; ; offset += 2) {
    const page = await call("cur", "GET", `/v1/curation/catalog?mediaType=movie&filter=all&sort=title&limit=2&offset=${offset}`);
    seen.push(...page.body.items.map((item) => item.key));
    if (!page.body.hasMore) break;
}
const visibleMovies = movies.filter((key) => key !== "movie_106");
check("paging by title covers every movie once", seen.length === visibleMovies.length && new Set(seen).size === seen.length, `${seen.length}/${visibleMovies.length}`);
for (const filter of ["needsWork", "almostPlayable", "untouched", "noTiers", "hasNewFrames", "noPoster", "published", "rejected"]) {
    res = await call("cur", "GET", `/v1/curation/catalog?mediaType=movie&filter=${filter}&sort=needsWork`);
    check(`filter ${filter} answers`, res.status === 200, JSON.stringify(res.body));
}
res = await call("cur", "GET", "/v1/curation/catalog?mediaType=movie&filter=published");
check("'published' lists what players see", JSON.stringify(res.body.items.map((i) => i.key).sort()) === JSON.stringify(["movie_102", "movie_104", "movie_105"]));
res = await call("cur", "GET", "/v1/curation/catalog?mediaType=movie&filter=rejected");
check("'rejected' finds the rejected title", res.body.items.map((i) => i.key).join() === "movie_106");

console.log("items, search, showcase");
res = await call("cur", "GET", "/v1/curation/items?keys=movie_101,nope,movie_102");
check("known keys only, in order", res.status === 200 && res.body.items.map((item) => item.key).join() === "movie_101,movie_102");
res = await call("mod", "GET", "/v1/curation/search?q=%D0%B0%D0%BB%D1%8C");
check("search drops people and marks our titles", res.status === 200 && res.body.results.length === 3
    && res.body.results.find((hit) => hit.key === "movie_101")?.item?.key === "movie_101"
    && res.body.results.find((hit) => hit.key === "movie_42")?.item === null);
tmdbCalls.length = 0;
res = await call("mod", "GET", "/v1/curation/showcase?list=known&mediaType=movie&decade=1990&genre=18");
check("showcase 'known' is discover by vote count with filters", res.status === 200 && res.body.hasMore === true
    && tmdbCalls[0].includes("sort_by=vote_count.desc") && tmdbCalls[0].includes("with_genres=18")
    && tmdbCalls[0].includes("primary_release_date.gte=1990-01-01") && tmdbCalls[0].includes("primary_release_date.lte=1999-12-31"), JSON.stringify(tmdbCalls));
check("showcase carries our standing", res.body.results.find((hit) => hit.key === "movie_101")?.item !== null
    && res.body.results.find((hit) => hit.key === "movie_4242")?.item === null);
res = await call("mod", "GET", "/v1/curation/showcase?list=trending&mediaType=movie");
check("trending uses the trending list", res.status === 200 && tmdbCalls.at(-1).startsWith("/3/trending/movie/week"));
res = await call("mod", "GET", "/v1/curation/showcase?list=bogus");
check("unknown list is 400", res.status === 400);

// ------------------------------------------------------------------ workbench

console.log("open imports and marks presence");
res = await call("mod", "POST", "/v1/curation/titles/movie_4242/open", {});
check("an unknown title is imported and opened", res.status === 200 && res.body.imported === true && res.body.images.length === 8, JSON.stringify(res.body).slice(0, 300));
check("the best clean poster is chosen", row("movie_4242").poster_url === "/clean-best.jpg", row("movie_4242").poster_url);
check("an imported poster is marked automatic", row("movie_4242").poster_auto === 1);
check("presence is mine", res.body.item.workedBy?.isMine === true && res.body.item.workedBy.name === "Аня");
res = await call("cur", "GET", "/v1/curation/queue?limit=50");
check("someone else's open title leaves my queue", !res.body.items.some((item) => item.key === "movie_4242"));
res = await call("mod", "GET", "/v1/curation/queue?limit=50");
check("but not the opener's", res.body.items.some((item) => item.key === "movie_4242"));
res = await call("cur", "POST", "/v1/curation/titles/movie_4242/open", {});
check("opening anyway works and says who else is there", res.status === 200 && res.body.imported === false && res.body.alsoWorking?.name === "Аня");
await call("mod", "POST", "/v1/curation/titles/movie_4242/close");
check("closing someone else's mark leaves it", row("movie_4242").worked_by === "cur");
res = await call("cur", "POST", "/v1/curation/titles/movie_4242/close");
check("closing my own clears it", row("movie_4242").worked_by === null && res.body.item.workedBy === null);
res = await call("mod", "POST", "/v1/curation/titles/nope/open", {});
check("a garbage key is 404", res.status === 404);

console.log("verdicts, undo and publishing");
res = await call("mod", "POST", "/v1/curation/titles/movie_4242/open", {});
const classic = res.body.images.map((image) => image.id);
res = await call("mod", "POST", "/v1/curation/titles/movie_4242/verdicts", {
    verdicts: classic.slice(0, 5).map((imageId, i) => ({ imageId, status: "approved", difficultyTier: ["hard", "medium", "easy"][i % 3] }))
});
check("a delta save keeps the title open", res.status === 200 && res.body.item.workedBy?.isMine === true, JSON.stringify(res.body).slice(0, 200));
res = await call("mod", "POST", "/v1/curation/titles/movie_4242/verdicts", { verdicts: [{ imageId: classic[5], status: "approved" }] });
check("approving without a tier is refused", res.status === 400 && row("movie_4242").approved_images === 5, JSON.stringify(res.body));
check("5 approved: not published", row("movie_4242").approved_images === 5 && row("movie_4242").published === 0);
await call("mod", "POST", "/v1/curation/titles/movie_4242/verdicts", {
    verdicts: [{ imageId: classic[5], status: "approved", difficultyTier: "hard" }, { imageId: classic[6], status: "rejected" }]
});
check("6 approved, one unjudged: auto waits", row("movie_4242").approved_images === 6 && row("movie_4242").unjudged_images === 1 && row("movie_4242").published === 0);
res = await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { publishMode: "on" });
check("'on' publishes early", res.status === 200 && row("movie_4242").published === 1, JSON.stringify(res.body));
await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { publishMode: "auto" });
check("back to auto withdraws it", row("movie_4242").published === 0);
await call("mod", "POST", "/v1/curation/titles/movie_4242/verdicts", { verdicts: [{ imageId: classic[6], status: "pending" }] });
const undone = db.db.prepare("SELECT status, moderator_status FROM media_images WHERE id = ?").get(classic[6]);
check("undo sends a frame back to unjudged", undone.status === "pending" && undone.moderator_status === null && row("movie_4242").unjudged_images === 2);
await call("mod", "POST", "/v1/curation/titles/movie_4242/verdicts", { verdicts: [], rejectRemaining: true, close: true });
check("finishing rejects the rest and closes", row("movie_4242").unjudged_images === 0 && row("movie_4242").worked_by === null);
check("auto publishes the finished title", row("movie_4242").published === 1 && row("movie_4242").work_weight === 0);
await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { posterURL: null });
check("taking the poster away unpublishes", row("movie_4242").published === 0);
res = await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { posterURL: "/clean-best.jpg" });
check("a chosen poster is no longer automatic", row("movie_4242").poster_auto === 0 && res.body.posterAuto === false, JSON.stringify(res.body).slice(0, 200));
await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { publishMode: "off" });
check("'off' holds a ready title back", row("movie_4242").published === 0);
await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { publishMode: "auto" });
check("and auto lets it back", row("movie_4242").published === 1);
res = await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { publishMode: "maybe" });
check("an unknown mode is 400", res.status === 400);
await call("mod", "POST", "/v1/catalog/items/movie_4242/reject", { reason: "тест" });
check("rejecting unpublishes", row("movie_4242").published === 0);
await call("mod", "POST", "/v1/catalog/items/movie_4242/reset");
check("reset starts over and returns to the queue", row("movie_4242").work_weight > 0 && row("movie_4242").unjudged_images === 8);

console.log("a 200-frame title saves in one go");
addTitle("movie_900", { title: "Большой", popularity: 5, frames: judged(0, 0, 200) });
await refreshMediaCounters({ DB: db }, "movie_900");
const bigIds = db.db.prepare("SELECT id FROM media_images WHERE media_key = 'movie_900' ORDER BY id").all().map((r) => r.id);
res = await call("me", "POST", "/v1/curation/titles/movie_900/verdicts", {
    verdicts: [
        ...bigIds.slice(0, 120).map((imageId) => ({ imageId, status: "approved", difficultyTier: "easy" })),
        ...bigIds.slice(120, 150).map((imageId) => ({ imageId, status: "rejected" }))
    ],
    rejectRemaining: true
});
const bigState = db.db.prepare(
    "SELECT status, COUNT(*) AS n FROM media_images WHERE media_key = 'movie_900' GROUP BY status ORDER BY status"
).all().map((r) => `${r.status}:${r.n}`).join();
check("past D1's 100 parameters without an error", res.status === 200 && bigState === "approved:120,rejected:80", `${res.status} ${bigState}`);

console.log("old surface is gone");
for (const [method, path] of [
    ["GET", "/v1/curation/queue/titles"], ["POST", "/v1/curation/queue/claim"], ["GET", "/v1/curation/batches"],
    ["POST", "/v1/curation/leases/movie_101"], ["GET", "/v1/curation/contested"], ["GET", "/v1/curation/reports"],
    ["POST", "/v1/catalog/items/movie_101/curate"]
]) {
    res = await call("me", method, path, method === "POST" ? {} : undefined);
    check(`${method} ${path} is 404`, res.status === 404, `${res.status}`);
}

// ------------------------------------------------------------------ reports

console.log("reports");
const reported = db.db.prepare("SELECT id FROM media_images WHERE media_key = 'movie_102' LIMIT 2").all();
for (const [index, image] of reported.entries()) {
    db.db.prepare("INSERT INTO image_reports (image_id, uid, reason, weight, created_at) VALUES (?, ?, ?, 1, ?)")
        .run(image.id, index ? "plain" : "cur", index ? "poster" : "bad_quality", now);
}
res = await call("mod", "GET", "/v1/curation/signals/reports");
check("grouped by title", res.status === 200 && res.body.titles.length === 1 && res.body.titles[0].frameIds.length === 2, JSON.stringify(res.body).slice(0, 300));
res = await call("mod", "GET", "/v1/curation/home");
check("the report badge counts frames", res.body.badges.reports === 2, JSON.stringify(res.body.badges));
res = await call("me", "GET", "/v1/admin/stats");
check("stats count published titles", res.status === 200 && res.body.items.every((kind) => "published" in kind), JSON.stringify(res.body.items));

console.log("usage");
res = await call("me", "GET", "/v1/admin/usage");
check("usage without a token says so", res.status === 503 && res.body.error === "usage_unavailable", JSON.stringify(res.body));
env.CF_ANALYTICS_TOKEN = "token";
env.CF_ACCOUNT_ID = "account";
res = await call("mod", "GET", "/v1/admin/usage");
check("a moderator cannot see usage", res.status === 403);
res = await call("me", "GET", "/v1/admin/usage");
check("usage sums every group", res.status === 200 && res.body.workers.requests === 1500 && res.body.d1.rowsWritten === 4000 && res.body.limits.rowsRead === 5000000, JSON.stringify(res.body));
check("usage resets at the next UTC midnight", res.body.resetsAt % 86400000 === 0 && res.body.resetsAt > Date.now());
check("usage asks for this account", graphqlCalls[0]?.variables.account === "account" && graphqlCalls[0].variables.date === new Date().toISOString().slice(0, 10));
await call("me", "GET", "/v1/admin/usage");
check("usage is cached for a minute", graphqlCalls.length === 1);

console.log("silencing a reporter");
const silencedFrame = db.db.prepare("SELECT id FROM media_images WHERE media_key = 'movie_103' LIMIT 1").get().id;
db.db.prepare("INSERT INTO image_reports (image_id, uid, reason, weight, created_at) VALUES (?, 'plain', 'not_a_frame', 5, ?)").run(silencedFrame, now);
db.db.prepare("UPDATE media_images SET report_weight = 5, status = 'rejected' WHERE id = ?").run(silencedFrame);
res = await call("mod", "PATCH", "/v1/admin/users/plain", { reportsCount: false });
check("a moderator cannot silence", res.status === 403);
res = await call("me", "PATCH", "/v1/admin/users/plain", { reportsCount: false });
const silenced = db.db.prepare("SELECT status, report_weight FROM media_images WHERE id = ?").get(silencedFrame);
check("silenced reports stop hiding frames", res.status === 200 && silenced.status === "pending" && silenced.report_weight === 0, JSON.stringify(silenced));
res = await call("me", "GET", "/v1/admin/users");
check("the user list shows it", res.body.users.find((u) => u.uid === "plain")?.reportsCount === false);
await call("me", "PATCH", "/v1/admin/users/plain", { reportsCount: true });

// ------------------------------------------------------------------ round

console.log("round");
const playable = db.db.prepare(
    "SELECT key FROM media_items WHERE media_type = 'movie' AND published = 1 AND approved_images >= 6 ORDER BY key"
).all().map((r) => r.key);
check("several movies are playable", playable.length >= 3, JSON.stringify(playable));

const picks = new Map();
let onlyApproved = true;
for (let i = 0; i < 400; i += 1) {
    const round = await call("plain", "GET", "/v1/round/next?mediaType=movie");
    if (round.status !== 200) { picks.set(`error ${round.status}`, round.body); break; }
    picks.set(round.body.item.key, (picks.get(round.body.item.key) ?? 0) + 1);
    const approvedIds = new Set(db.db.prepare("SELECT id FROM media_images WHERE media_key = ? AND status = 'approved'")
        .all(round.body.item.key).map((r) => r.id));
    if (round.body.frames.length !== 6 || ![...round.body.frames, ...round.body.spareFrames].every((f) => approvedIds.has(f.id))) onlyApproved = false;
}
check("picks only published titles, each of them", JSON.stringify([...picks.keys()].sort()) === JSON.stringify(playable), JSON.stringify([...picks]));
check("six approved frames and approved spares", onlyApproved);
check("no title starved", Math.min(...picks.values()) > 400 / playable.length / 4, JSON.stringify([...picks]));

db.db.prepare("INSERT INTO daily_overrides (date, media_key, created_at) VALUES ('2999-01-01', ?, 0)").run(playable[0]);
let dailyLeaked = false;
for (let i = 0; i < 80; i += 1) {
    if ((await call("plain", "GET", "/v1/round/next?mediaType=movie")).body?.item?.key === playable[0]) dailyLeaked = true;
}
check("a scheduled daily film is not dealt at random", !dailyLeaked);
db.db.prepare("UPDATE daily_overrides SET date = '2000-01-01' WHERE media_key = ?").run(playable[0]);
let pastDailyDealt = false;
for (let i = 0; i < 200 && !pastDailyDealt; i += 1) {
    if ((await call("plain", "GET", "/v1/round/next?mediaType=movie")).body?.item?.key === playable[0]) pastDailyDealt = true;
}
check("after its day it is dealt again", pastDailyDealt);
db.db.prepare("DELETE FROM daily_overrides WHERE media_key = ?").run(playable[0]);

for (const key of playable.slice(1)) db.db.prepare("INSERT INTO watched_media (uid, media_key, added_at) VALUES ('plain', ?, ?)").run(key, now);
let onlyUnseen = true;
for (let i = 0; i < 20; i += 1) {
    if ((await call("plain", "GET", "/v1/round/next?mediaType=movie")).body?.item?.key !== playable[0]) onlyUnseen = false;
}
check("watched titles are skipped", onlyUnseen);
db.db.prepare("INSERT INTO watched_media (uid, media_key, added_at) VALUES ('plain', ?, ?)").run(playable[0], now);
const exhausted = await call("plain", "GET", "/v1/round/next?mediaType=movie");
check("everything watched: pool_exhausted", exhausted.status === 404 && exhausted.body.error === "pool_exhausted"
    && exhausted.body.matchingTotal === playable.length, JSON.stringify(exhausted));

const user = (uid) => db.db.prepare("SELECT * FROM users WHERE uid = ?").get(uid);
check("a reporter under the bar weighs 0", await reporterWeight({ DB: db }, user("cur")) === 0);
for (let i = 0; i < 5; i += 1) db.db.prepare("INSERT OR IGNORE INTO watched_media (uid, media_key, added_at) VALUES ('plain', ?, ?)").run(`movie_x${i}`, now);
check("a reporter over the bar weighs the multiplier", await reporterWeight({ DB: db }, user("plain")) === user("plain").report_multiplier);

console.log("daily scheduling");
res = await call("mod", "PUT", "/v1/admin/daily/2999-02-01", { mediaKey: "movie_101" });
check("an unpublished title is refused", res.status === 400, JSON.stringify(res.body));

db.db.prepare("INSERT INTO daily_overrides (date, media_key, created_at) VALUES ('2999-03-01', ?, 0)").run(playable[0]);
res = await call("mod", "GET", "/v1/admin/daily/2999-03-01");
check("a day shows its approved frames", res.status === 200 && res.body.images.length >= 6 && res.body.editable === true, JSON.stringify(res.body).slice(0, 200));
const own = res.body.images.slice(0, 6).map((image) => image.id).reverse();
res = await call("mod", "PUT", "/v1/admin/daily/2999-03-01/frames", { frameIds: own });
const stored = db.db.prepare("SELECT frame_ids, spare_ids FROM daily_overrides WHERE date = '2999-03-01'").get();
check("a moderator's own order is stored as is", res.status === 200 && stored.frame_ids === JSON.stringify(own), JSON.stringify(res.body));
check("spares never repeat the chosen frames", JSON.parse(stored.spare_ids).every((id) => !own.includes(id)));
res = await call("mod", "PUT", "/v1/admin/daily/2999-03-01/frames", { frameIds: [own[0], own[0], own[1], own[2], own[3], own[4]] });
check("a repeated frame is refused", res.status === 400);
res = await call("mod", "PUT", "/v1/admin/daily/2999-03-01/frames", { reroll: true });
check("a re-roll lays out six frames", res.status === 200 && res.body.frameIds.length === 6, JSON.stringify(res.body));
db.db.prepare("INSERT INTO daily_results (uid, date, media_key, was_correct, attempts_used, completed_at) VALUES ('plain', '2000-03-01', ?, 1, 1, 0)").run(playable[0]);
db.db.prepare("UPDATE daily_overrides SET date = '2000-03-01' WHERE date = '2999-03-01'").run();
res = await call("mod", "PUT", "/v1/admin/daily/2000-03-01/frames", { reroll: true });
check("a played day is locked", res.status === 409, JSON.stringify(res.body));
db.db.prepare("DELETE FROM daily_overrides WHERE date = '2000-03-01'").run();
db.db.prepare("DELETE FROM daily_results WHERE date = '2000-03-01'").run();

// ------------------------------------------------------------------ deletion

console.log("account deletion");
const target = db.db.prepare("SELECT id FROM media_images WHERE media_key = 'movie_103' AND moderator_status IS NULL AND status = 'pending' LIMIT 1").get();
db.db.prepare("UPDATE users SET report_multiplier = 5 WHERE uid = 'plain'").run();
res = await call("plain", "POST", "/v1/curation/report", { imageId: target.id, reason: "not_a_frame" });
check("a heavy report hides the frame", res.status === 200 && db.db.prepare("SELECT status FROM media_images WHERE id = ?").get(target.id).status === "rejected", JSON.stringify(res));
db.db.prepare("INSERT INTO refresh_tokens (token_hash, uid, issued_at, expires_at) VALUES ('h-plain', 'plain', 0, 9999999999999)").run();
res = await call("plain", "DELETE", "/v1/profile");
const left = (table) => db.db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE uid = 'plain'`).get().n;
check("delete answers 204", res.status === 204, JSON.stringify(res));
check("user, tokens, watched and reports are gone", left("users") + left("refresh_tokens") + left("watched_media") + left("image_reports") === 0);
const restored = db.db.prepare("SELECT status, report_weight FROM media_images WHERE id = ?").get(target.id);
check("their report stops hiding the frame", restored.status === "pending" && restored.report_weight === 0, JSON.stringify(restored));
check("the old token no longer works", (await call("plain", "GET", "/v1/profile")).status === 401);
db.db.prepare("UPDATE users SET role = 'moderator' WHERE role = 'admin' AND uid != 'me'").run();
check("the last admin cannot delete themselves", (await call("me", "DELETE", "/v1/profile")).status === 409);

console.log("playlist delete");
const draft = await call("mod", "POST", "/v1/playlists", { title: "Черновик", mediaType: "movie" });
res = await call("mod", "DELETE", `/v1/playlists/${draft.body.id}`);
check("a moderator deletes a draft", res.status === 204 && !db.db.prepare("SELECT 1 FROM playlists WHERE id = ?").get(draft.body.id));
const live = await call("mod", "POST", "/v1/playlists", { title: "Витрина", mediaType: "movie" });
db.db.prepare("UPDATE playlists SET published = 1 WHERE id = ?").run(live.body.id);
db.db.prepare("INSERT INTO playlist_progress (uid, playlist_id, media_key, state, updated_at) VALUES ('mod', ?, 'movie_x', 'completed', 0)").run(live.body.id);
check("a published one is admin-only", (await call("mod", "DELETE", `/v1/playlists/${live.body.id}`)).status === 403);
res = await call("me", "DELETE", `/v1/playlists/${live.body.id}`);
check("the admin deletes it with players' progress", res.status === 204
    && db.db.prepare("SELECT COUNT(*) AS n FROM playlist_progress WHERE playlist_id = ?").get(live.body.id).n === 0);

console.log("admin deletes users");
check("a moderator cannot delete accounts", (await call("mod", "DELETE", "/v1/admin/users/cur")).status === 403);
check("an admin cannot delete themselves here", (await call("me", "DELETE", "/v1/admin/users/me")).status === 400);
res = await call("me", "DELETE", "/v1/admin/users/cur");
check("the admin deletes a moderator", res.status === 204 && !user("cur"));

console.log("request limiter");
const hits = new Map();
env.REQUEST_LIMITER = { limit: async ({ key }) => {
    hits.set(key, (hits.get(key) ?? 0) + 1);
    return { success: hits.get(key) <= 3 };
} };
const statuses = [];
for (let i = 0; i < 4; i += 1) statuses.push((await call("mod", "GET", "/v1/profile")).status);
delete env.REQUEST_LIMITER;
check("the fourth request in the window is refused", JSON.stringify(statuses) === "[200,200,200,429]", JSON.stringify(statuses));
check("keyed by account", [...hits.keys()].every((key) => key === "REQUEST_LIMITER:mod"));

// ------------------------------------------------------------------ plans

console.log("query plans");
const baseFilters = { mediaType: "movie", genres: [], languages: [], query: "", yearFrom: null, yearTo: null, minApprovedImages: 6 };
const hot = {
    queue: [`SELECT * FROM media_items m WHERE m.work_weight > 0 AND (?1 IS NULL OR m.media_type = ?1)
             AND NOT (m.worked_by IS NOT NULL AND m.worked_by != ?2 AND m.worked_since > ?3)
             ORDER BY m.work_weight DESC, m.key LIMIT ?4`, [null, "cur", 0, 20]],
    catalogPopularity: ["SELECT * FROM media_items m WHERE m.media_type = ? AND m.status != 'rejected' ORDER BY m.popularity DESC, m.key LIMIT ? OFFSET ?", ["movie", 51, 0]],
    catalogTitle: ["SELECT * FROM media_items m WHERE m.media_type = ? AND m.status != 'rejected' ORDER BY m.title COLLATE NOCASE ASC, m.key LIMIT ? OFFSET ?", ["movie", 51, 0]],
    catalogRecent: ["SELECT * FROM media_items m WHERE m.media_type = ? AND m.status != 'rejected' ORDER BY m.created_at DESC, m.key LIMIT ? OFFSET ?", ["movie", 51, 0]],
    reportBadge: ["SELECT COUNT(DISTINCT image_id) AS n FROM image_reports WHERE dismissed_at IS NULL", []],
    roundFrames: ["SELECT * FROM media_images WHERE media_key = ? AND status = 'approved'", ["movie_101"]],
    reporterBar: ["SELECT COUNT(*) AS count FROM (SELECT 1 FROM watched_media WHERE uid = ? LIMIT ?)", ["plain", 5]]
};
for (const [name, filters] of Object.entries({
    roundPick: baseFilters,
    roundPickFiltered: { ...baseFilters, genres: [18, 35], languages: ["en"], yearFrom: 1990, yearTo: 2020 }
})) {
    const { where, bindings } = buildCatalogQuery(filters, { uid: "plain", excludeWatched: true, excludeDailyFrom: "2026-01-01" });
    hot[name] = [`SELECT m.key FROM media_items m INDEXED BY idx_media_shuffle WHERE ${where} AND m.shuffle_key >= ? ORDER BY m.shuffle_key LIMIT ?`,
        [...bindings, 0.5, 8]];
}
for (const [name, [sql, values]] of Object.entries(hot)) {
    const text = db.plan(sql, values).join(" | ");
    const scansFrames = /SCAN (i|media_images)\b/.test(text);
    const sorts = /TEMP B-TREE FOR ORDER BY/.test(text);
    const fullItems = /SCAN m\b(?! USING)/.test(text) || /SCAN media_items\b(?! USING)/.test(text);
    check(`${name}: no frame scan, no sort, no bare table scan`, !scansFrames && !sorts && !fullItems, `\n      ${text}`);
}

console.log(failures ? `\n${failures} FAILED` : "\nall passed");
process.exit(failures ? 1 : 0);
