// End-to-end checks of the real worker (src/index.js) against an in-memory
// database built from schema.sql. Run from CloudflareWorker/api:
//
//     node --no-warnings test/run.mjs

import { readFileSync } from "node:fs";
import { D1 } from "./d1.mjs";

const API = new URL("..", import.meta.url).pathname;
const SECRET = "test-secret-test-secret-test-secret-00";

const { default: worker } = await import(`${API}src/index.js`);
const { signJWT, sha256Hex } = await import(`${API}src/lib/crypto.js`);
const { REFRESH_RETRY_GRACE_MS } = await import(`${API}src/lib/auth.js`);
const { refreshMediaCounters, buildCatalogQuery } = await import(`${API}src/lib/media.js`);
const { reporterWeight } = await import(`${API}src/lib/limits.js`);
const { selectRoundFrames, seededRandom } = await import(`${API}src/lib/frames.js`);
const { stepDown } = await import(`${API}src/lib/catalogIndex.js`);
const { syncDueTitles } = await import(`${API}src/lib/sync.js`);
const { autoScheduleTomorrow } = await import(`${API}src/lib/daily.js`);
const { NIGHTLY_CRON } = await import(`${API}src/lib/scheduled.js`);

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
const tmdbTitles = new Map();
const imageChecks = [];
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
    if (target.hostname === "image.tmdb.org") {
        imageChecks.push(target.pathname);
        return new Response(null, { status: target.pathname.includes("gone") ? 404 : 200 });
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
    const details = target.pathname.match(/^\/3\/(movie|tv)\/(\d+)$/);
    if (details && tmdbTitles.has(Number(details[2]))) return reply(tmdbTitles.get(Number(details[2])));
    if (details) return reply({ id: Number(details[2]), vote_average: 7.26, vote_count: 1234 });
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
    return { status: response.status, body: text ? JSON.parse(text) : null, headers: response.headers };
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
check("back to auto keeps a published title out there", row("movie_4242").published === 1);
await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { publishMode: "off" });
await call("mod", "PATCH", "/v1/catalog/items/movie_4242", { publishMode: "auto" });
check("but auto does not bring back a withdrawn one with unjudged frames", row("movie_4242").published === 0);
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
check("a played day cannot be removed", (await call("mod", "DELETE", "/v1/admin/daily/2000-03-01")).status === 409);
db.db.prepare("DELETE FROM daily_overrides WHERE date = '2000-03-01'").run();
db.db.prepare("DELETE FROM daily_results WHERE date = '2000-03-01'").run();
db.db.prepare("INSERT INTO daily_overrides (date, media_key, created_at) VALUES (date('now'), ?, 0)").run(playable[0]);
res = await call("mod", "DELETE", `/v1/admin/daily/${new Date().toISOString().slice(0, 10)}`);
check("an unplayed today can be removed", res.status === 204, JSON.stringify(res.body));

// ------------------------------------------------------------------ cropped rounds

console.log("frames are cropped, not squeezed");
{
    const frames = ["hard", "hard", "medium", "medium", "easy", "easy"].map((tier, i) => ({
        id: i + 1, status: "approved", difficulty_tier: tier, difficulty_rank: null, tmdb_vote_average: i, tmdb_vote_count: i
    }));
    const tiersOf = (n) => selectRoundFrames(frames, n, { random: seededRandom(1) }).map((f) => f.difficulty_tier).join();
    check("six frames run hard to easy", tiersOf(6) === "hard,hard,medium,medium,easy,easy", tiersOf(6));
    check("three frames are the hardest three", tiersOf(3) === "hard,hard,medium", tiersOf(3));
    check("one frame is a hard one", tiersOf(1) === "hard");
    const six = selectRoundFrames(frames, 6, { random: seededRandom(5) }).map((f) => f.id);
    const two = selectRoundFrames(frames, 2, { random: seededRandom(5) }).map((f) => f.id);
    check("a short round is the start of the same layout", JSON.stringify(two) === JSON.stringify(six.slice(0, 2)));
    const pinned = frames.map((f) => (f.id === 6 ? { ...f, difficulty_rank: 1 } : f));
    check("a pinned rank keeps its place", selectRoundFrames(pinned, 2, { random: seededRandom(1) })[0].id === 6);
}

console.log("round by mediaKey");
const dealt = playable[1];
res = await call("mod", "GET", `/v1/round/next?mediaKey=${dealt}&frameCount=12`);
check("the phone's pick is dealt, at most six frames", res.status === 200 && res.body.item.key === dealt && res.body.frames.length === 6, JSON.stringify(res.body).slice(0, 200));
res = await call("mod", "GET", `/v1/round/next?mediaKey=${dealt}&frameCount=2`);
check("two frames when asked for two", res.status === 200 && res.body.frames.length === 2);
db.db.prepare("INSERT INTO daily_overrides (date, media_key, created_at) VALUES ('2999-05-01', ?, 0)").run(dealt);
res = await call("mod", "GET", `/v1/round/next?mediaKey=${dealt}`);
check("an upcoming daily is still dealt by key", res.status === 200);
db.db.prepare("DELETE FROM daily_overrides WHERE date = '2999-05-01'").run();
res = await call("mod", "GET", "/v1/round/next?mediaKey=movie_101");
check("an unpublished title says the index is stale", res.status === 404 && res.body.error === "not_playable", JSON.stringify(res.body));
res = await call("mod", "GET", "/v1/round/next?mediaKey=movie_nope");
check("an unknown title too", res.status === 404 && res.body.error === "not_playable");

console.log("finishing a round");
const watchedRow = (uid, key) => db.db.prepare("SELECT * FROM watched_media WHERE uid = ? AND media_key = ?").get(uid, key);
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: dealt, mode: "random", result: "correct", solvedAtFrame: 2, frameCount: 6 });
check("the first round counts", res.status === 200 && res.body.counted === true && res.body.repeat === false, JSON.stringify(res.body));
check("it is the title's statistic", res.body.stats.players === 1 && res.body.stats.solvedAtFrame[1] === 1, JSON.stringify(res.body.stats));
check("stored with frame and mode", watchedRow("mod", dealt).result === "correct" && watchedRow("mod", dealt).solved_at_frame === 2
    && watchedRow("mod", dealt).mode === "random" && watchedRow("mod", dealt).plays === 1);
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: dealt, mode: "random", result: "wrong", frameCount: 6 });
check("a replay is marked and does not count", res.body.repeat === true && res.body.counted === false && res.body.stats.players === 1);
check("a replay keeps the first result", watchedRow("mod", dealt).result === "correct" && watchedRow("mod", dealt).plays === 2 && watchedRow("mod", dealt).solved === 1);
res = await call("me", "POST", "/v1/round/finish", { mediaKey: dealt, mode: "random", result: "wrong", frameCount: 3, counts: false });
check("a round with a broken frame marks it seen without counting", res.body.counted === false && watchedRow("me", dealt).result === null
    && watchedRow("me", dealt).plays === 1 && res.body.stats.players === 1);
res = await call("me", "POST", "/v1/round/finish", { mediaKey: dealt, mode: "random", result: "correct", solvedAtFrame: 1, frameCount: 3 });
check("and the next one is already a replay", res.body.repeat === true && res.body.counted === false && watchedRow("me", dealt).solved === 1);
for (const [label, body] of [
    ["solvedAtFrame past frameCount", { mediaKey: dealt, mode: "random", result: "correct", solvedAtFrame: 4, frameCount: 3 }],
    ["seven frames", { mediaKey: dealt, mode: "random", result: "wrong", frameCount: 7 }],
    ["an unknown mode", { mediaKey: dealt, mode: "tmdb", result: "wrong", frameCount: 6 }],
    ["a correct answer without its frame", { mediaKey: dealt, mode: "random", result: "correct", frameCount: 6 }]
]) {
    res = await call("mod", "POST", "/v1/round/finish", body);
    check(`${label} is 400`, res.status === 400, JSON.stringify(res.body));
}
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: "movie_nope", mode: "random", result: "wrong", frameCount: 6 });
check("an unknown title is 404", res.status === 404);

const list = await call("mod", "POST", "/v1/playlists", { title: "Финиш", mediaType: "movie" });
await call("mod", "PUT", `/v1/playlists/${list.body.id}/items`, { mediaKeys: [playable[2]] });
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: playable[2], mode: "playlist", playlistId: list.body.id, result: "correct", solvedAtFrame: 3, frameCount: 6 });
const progressRow = db.db.prepare("SELECT * FROM playlist_progress WHERE uid = 'mod' AND playlist_id = ?").get(list.body.id);
check("a playlist round records its progress", res.status === 200 && progressRow?.was_correct === 1 && progressRow.attempts_used === 3
    && res.body.playlist.progress.answered === 1, JSON.stringify(res.body));
check("and marks the title seen for the random pool", watchedRow("mod", playable[2])?.mode === "playlist" && res.body.counted === true);
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: playable[0], mode: "playlist", playlistId: list.body.id, result: "wrong", frameCount: 6 });
check("a title outside the playlist is 404", res.status === 404);

const today = new Date().toISOString().slice(0, 10);
db.db.prepare("INSERT INTO daily_overrides (date, media_key, created_at) VALUES (?, ?, 0)").run(today, playable[0]);
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: playable[1], mode: "daily", date: today, result: "wrong", frameCount: 6 });
check("a daily with the wrong film is 400", res.status === 400);
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: playable[0], mode: "daily", date: today, result: "correct", solvedAtFrame: 4, frameCount: 6 });
check("a daily writes the day's result", res.status === 200 && res.body.daily.dailyStreak === 1
    && db.db.prepare("SELECT attempts_used FROM daily_results WHERE uid = 'mod' AND date = ?").get(today)?.attempts_used === 4, JSON.stringify(res.body));
check("the day's statistic, not the title's", res.body.stats.players === 1 && res.body.stats.solvedAtFrame[3] === 1);
check("a daily marks the title seen without counting it", watchedRow("mod", playable[0])?.solved === 1 && watchedRow("mod", playable[0]).result === null);
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: playable[0], mode: "daily", date: today, result: "wrong", frameCount: 6 });
check("a day is played once", res.status === 200 && res.body.alreadyRecorded === true && res.body.daily.wasCorrect === true
    && watchedRow("mod", playable[0]).plays === 1);
res = await call("plain", "PATCH", "/v1/profile", { statsExcluded: true });
check("a player cannot leave the statistics", res.status === 403);
res = await call("mod", "PATCH", "/v1/profile", { statsExcluded: true });
check("a moderator can", res.status === 200 && res.body.user.statsExcluded === true);
db.db.prepare("DELETE FROM daily_results WHERE date = ?").run(today);
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: playable[0], mode: "daily", date: today, result: "correct", solvedAtFrame: 2, frameCount: 6 });
check("an excluded daily keeps the streak but not the statistic", res.status === 200 && res.body.daily.wasCorrect === true && res.body.stats.players === 0
    && db.db.prepare("SELECT counted FROM daily_results WHERE uid = 'mod' AND date = ?").get(today)?.counted === 0, JSON.stringify(res.body));
res = await call("mod", "POST", "/v1/round/finish", { mediaKey: playable[3], mode: "random", result: "correct", solvedAtFrame: 1, frameCount: 6 });
check("an excluded round is seen but not counted", res.status === 200 && res.body.counted === false && res.body.repeat === false
    && watchedRow("mod", playable[3]).result === null && watchedRow("mod", playable[3]).plays === 1, JSON.stringify(res.body));
await call("mod", "PATCH", "/v1/profile", { statsExcluded: false });
db.db.prepare("DELETE FROM watched_media WHERE uid = 'mod' AND media_key = ?").run(playable[3]);
db.db.prepare("DELETE FROM daily_results WHERE date = ?").run(today);
db.db.prepare("DELETE FROM daily_overrides WHERE date = ?").run(today);

res = await call("mod", "PATCH", `/v1/profile/watched/${dealt}`, { hidden: true });
check("a title can be hidden", res.status === 200 && res.body.hidden === true && watchedRow("mod", dealt).plays === 2);
res = await call("mod", "PATCH", "/v1/profile/watched/movie_unplayed", { hidden: true });
check("even one never played", res.status === 200 && res.body.plays === 0 && res.body.sources.length === 0);
res = await call("mod", "GET", "/v1/profile/watched");
const restoredEntry = res.body.watched.find((entry) => entry.mediaKey === dealt);
check("the backup restores everything the phone keeps", restoredEntry?.hidden === true && restoredEntry.result === "correct"
    && restoredEntry.solvedAtFrame === 2 && restoredEntry.plays === 2 && restoredEntry.solved === true && restoredEntry.lastPlayedAt > 0, JSON.stringify(restoredEntry));

// ------------------------------------------------------------------ catalogue index

console.log("catalogue index");
check("steps round down", stepDown(7.26, 0.5) === 7 && stepDown(7.5, 0.5) === 7.5 && stepDown(1299, 100) === 1200 && stepDown(0.3, 0.1) === 0.3);
check("ratings start empty", row("movie_102").vote_count === null);
for (let run = 0; run < 2; run += 1) await worker.scheduled({ cron: "*/30 * * * *", scheduledTime: Date.now() }, env, {});
check("the cron fills ratings in a few titles a run", db.db.prepare("SELECT COUNT(*) AS n FROM media_items WHERE vote_count IS NULL").get().n === 0
    && row("movie_102").vote_count === 1234);
const firstVersion = db.db.prepare("SELECT value FROM app_config WHERE key = 'catalogIndexVersion'").get()?.value;
check("and builds the index", /^v1-[0-9a-f]{16}$/.test(firstVersion ?? ""), firstVersion);
res = await call("plain", "GET", "/v1/catalog/index");
const published = db.db.prepare("SELECT key FROM media_items WHERE published = 1 ORDER BY key").all().map((r) => r.key);
check("the index lists published titles", res.status === 200 && JSON.stringify(res.body.items.map((i) => i.key)) === JSON.stringify(published), JSON.stringify(res.body).slice(0, 300));
check("with stepped numbers and no names", res.body.items.every((i) => i.rating === 7 && i.votes === 1200 && !("title" in i)) && res.body.steps.rating === 0.5);
check("the version is in the body and the header", res.body.version === firstVersion && res.headers.get("X-Catalog-Version") === firstVersion);
res = await call("plain", "GET", "/v1/profile");
check("every response carries the version", res.headers.get("X-Catalog-Version") === firstVersion);

await worker.scheduled({}, env, {});
const rowsBefore = db.db.prepare("SELECT COUNT(*) AS n FROM catalog_index").get().n;
await worker.scheduled({}, env, {});
check("a clean index is not rebuilt", db.db.prepare("SELECT COUNT(*) AS n FROM catalog_index").get().n === rowsBefore);
await call("mod", "PATCH", `/v1/catalog/items/${published[0]}`, { publishMode: "off" });
check("unpublishing marks the index dirty", db.db.prepare("SELECT 1 FROM app_config WHERE key = 'catalogIndexDirty'").get() !== undefined);
await worker.scheduled({}, env, {});
const secondVersion = db.db.prepare("SELECT value FROM app_config WHERE key = 'catalogIndexVersion'").get().value;
check("the rebuild drops the title under a new version", secondVersion !== firstVersion
    && !JSON.parse(db.db.prepare("SELECT body FROM catalog_index WHERE version = ?").get(secondVersion).body).items.some((i) => i.key === published[0]));
check("the old version stays for a while", db.db.prepare("SELECT 1 FROM catalog_index WHERE version = ?").get(firstVersion) !== undefined);
await call("mod", "PATCH", `/v1/catalog/items/${published[0]}`, { publishMode: "auto" });
await worker.scheduled({}, env, {});
check("the same catalogue hashes to the same version", db.db.prepare("SELECT value FROM app_config WHERE key = 'catalogIndexVersion'").get().value === firstVersion);

// ------------------------------------------------------------------ background upkeep

console.log("sync with TMDB");
{
    addTitle("movie_7777", { title: "Синк", popularity: 3, frames: judged(8, 1, 0) });
    const longAgo = Date.now() - 200 * 24 * 60 * 60 * 1000;
    db.db.prepare("UPDATE media_items SET last_synced_at = ?, release_year = 1990, original_language = 'en', vote_average = 5, vote_count = 100 WHERE key = 'movie_7777'").run(longAgo);
    const f = db.db.prepare("SELECT * FROM media_images WHERE media_key = 'movie_7777' ORDER BY id").all();
    db.db.prepare("UPDATE media_images SET file_path = '/gone-a.jpg' WHERE id = ?").run(f[0].id);
    db.db.prepare("UPDATE media_images SET file_path = '/moved.jpg' WHERE id = ?").run(f[1].id);
    db.db.prepare("UPDATE media_images SET missing_at = 1 WHERE id = ?").run(f[2].id);
    await refreshMediaCounters({ DB: db }, "movie_7777");
    check("a title with a missing frame counts it", row("movie_7777").missing_images === 1 && row("movie_7777").approved_images === 7 && row("movie_7777").published === 1);

    const listed = f.slice(2, 8).map((frame) => frame.file_path);
    tmdbTitles.set(7777, {
        id: 7777, title: "Синк 2", original_title: "Sync", release_date: "1990-01-01", original_language: "en",
        popularity: 4, vote_average: 8.3, vote_count: 4321, genres: [{ id: 18 }],
        images: { posters: [], backdrops: [
            ...listed.map((path) => ({ file_path: path, iso_639_1: null, vote_average: 9.9, vote_count: 99 })),
            { file_path: "/new1.jpg", iso_639_1: null, vote_average: 1, vote_count: 1, width: 1920, height: 1080, aspect_ratio: 1.778 },
            { file_path: "/new2.jpg", iso_639_1: null, vote_average: 1, vote_count: 1 },
            { file_path: "/titled.jpg", iso_639_1: "en", vote_average: 1, vote_count: 1 }
        ] }
    });

    db.db.prepare("INSERT INTO daily_overrides (date, media_key, frame_ids, spare_ids, frame_count, created_at) VALUES ('2999-07-01', 'movie_7777', ?, ?, 6, 0)")
        .run(JSON.stringify(f.slice(0, 6).map((x) => x.id).reverse()), JSON.stringify([f[6].id, f[7].id]));
    db.db.prepare("INSERT INTO daily_overrides (date, media_key, frame_ids, spare_ids, frame_count, created_at) VALUES ('2999-07-02', 'movie_7777', ?, '[]', 6, 0)")
        .run(JSON.stringify(f.slice(0, 6).map((x) => x.id)));
    db.db.prepare("INSERT INTO daily_results (uid, date, media_key, was_correct, attempts_used, completed_at) VALUES ('mod', '2999-07-02', 'movie_7777', 1, 1, 0)").run();

    imageChecks.length = 0;
    const outcome = await syncDueTitles(env, { limit: 50 });
    const synced = outcome?.synced?.find((entry) => entry.key === "movie_7777");
    const frame = (id) => db.db.prepare("SELECT * FROM media_images WHERE id = ?").get(id);
    check("the due title is synced", synced?.complete === true, JSON.stringify(outcome));
    check("its own fields are rewritten", row("movie_7777").title === "Синк 2" && row("movie_7777").vote_count === 4321
        && row("movie_7777").last_synced_at > longAgo);
    check("genres follow TMDB", db.db.prepare("SELECT group_concat(genre_id) AS g FROM media_genres WHERE media_key = 'movie_7777'").get().g === "18");
    check("frames already known are not rewritten", frame(f[3].id).tmdb_vote_average === f[3].tmdb_vote_average);
    const fresh = db.db.prepare("SELECT status, moderator_status FROM media_images WHERE media_key = 'movie_7777' AND file_path IN ('/new1.jpg', '/new2.jpg')").all();
    check("new stills arrive unjudged, titled ones not at all", fresh.length === 2 && fresh.every((x) => x.status === "pending" && x.moderator_status === null)
        && !db.db.prepare("SELECT 1 FROM media_images WHERE file_path = '/titled.jpg'").get());
    check("only unlisted frames still in play are checked", JSON.stringify(imageChecks.sort()) === JSON.stringify(["/t/p/w92/gone-a.jpg", "/t/p/w92/moved.jpg"]), JSON.stringify(imageChecks));
    check("a 404 marks a frame missing", frame(f[0].id).missing_at > 0 && frame(f[0].id).status === "approved");
    check("an unlisted frame that still loads is left alone", frame(f[1].id).missing_at === null);
    check("a frame TMDB lists again is back", frame(f[2].id).missing_at === null);
    check("new frames keep a published title published", row("movie_7777").published === 1 && row("movie_7777").unjudged_images === 2
        && row("movie_7777").missing_images === 1 && row("movie_7777").approved_images === 7);
    check("a rating change flags the index", db.db.prepare("SELECT 1 FROM app_config WHERE key = 'catalogIndexDirty'").get() !== undefined);

    const day = db.db.prepare("SELECT * FROM daily_overrides WHERE date = '2999-07-01'").get();
    const dayFrames = JSON.parse(day.frame_ids);
    check("an unplayed daily swaps the missing frame for a spare", !dayFrames.includes(f[0].id) && dayFrames.length === 6
        && dayFrames.includes(f[6].id) && day.replaced_at > 0, day.frame_ids);
    check("in the same place", dayFrames[5] === f[6].id && JSON.stringify(dayFrames.slice(0, 5)) === JSON.stringify(f.slice(1, 6).map((x) => x.id).reverse()));
    check("and its spares are all in play", JSON.parse(day.spare_ids).every((id) => frame(id).missing_at === null && !dayFrames.includes(id)));
    check("a played daily is left as it was", db.db.prepare("SELECT replaced_at FROM daily_overrides WHERE date = '2999-07-02'").get().replaced_at === null);
    res = await call("mod", "GET", "/v1/admin/daily/2999-07-01");
    check("the moderator sees the swap", res.body.replacedAt > 0 && !res.body.images.some((image) => image.id === f[0].id), JSON.stringify(res.body).slice(0, 200));
    await call("mod", "PUT", "/v1/admin/daily/2999-07-01/frames", { reroll: true });
    check("re-laying a day clears the flag", db.db.prepare("SELECT replaced_at FROM daily_overrides WHERE date = '2999-07-01'").get().replaced_at === null);
    db.db.prepare("DELETE FROM daily_results WHERE date = '2999-07-02'").run();
    db.db.prepare("DELETE FROM daily_overrides WHERE media_key = 'movie_7777'").run();

    check("a synced title is not due again", (await syncDueTitles(env, { limit: 50 }))?.synced?.some((entry) => entry.key === "movie_7777") !== true);

    res = await call("mod", "POST", "/v1/catalog/items/movie_7777/reimport");
    check("a manual check right after a sync is refused", res.status === 429, JSON.stringify(res.body));
    const before = row("movie_7777");
    db.db.prepare("UPDATE media_items SET last_synced_at = ? WHERE key = 'movie_7777'").run(longAgo);
    tmdbTitles.get(7777).images.backdrops.push({ file_path: "/new3.jpg", iso_639_1: null, vote_average: 1, vote_count: 1 });
    res = await call("plain", "POST", "/v1/catalog/items/movie_7777/reimport");
    check("a player cannot run it", res.status === 403);
    res = await call("mod", "POST", "/v1/catalog/items/movie_7777/reimport");
    check("a manual check is the sync", res.status === 200 && res.body.newFrames === 1 && res.body.item.lastSyncedAt > longAgo
        && res.body.totalFrames === db.db.prepare("SELECT COUNT(*) AS n FROM media_images WHERE media_key = 'movie_7777'").get().n, JSON.stringify(res.body));
    check("and leaves known frames alone", frame(f[3].id).tmdb_vote_average === f[3].tmdb_vote_average && row("movie_7777").approved_images === before.approved_images);
    tmdbTitles.get(7777).images.backdrops.pop();

    let dealtMissing = false;
    for (let i = 0; i < 20; i += 1) {
        const round = await call("mod", "GET", "/v1/round/next?mediaKey=movie_7777");
        if ([...round.body.frames, ...round.body.spareFrames].some((x) => x.id === f[0].id)) dealtMissing = true;
    }
    check("a missing frame is never dealt", !dealtMissing);

    res = await call("mod", "GET", "/v1/curation/home");
    check("the missing badge counts titles", res.body.badges.missingFrames >= 1, JSON.stringify(res.body.badges));
    res = await call("mod", "GET", "/v1/curation/catalog?mediaType=movie&filter=missingFrames");
    check("and the filter finds them", res.status === 200 && res.body.items.some((item) => item.key === "movie_7777" && item.missingImages === 1));
    res = await call("plain", "POST", `/v1/curation/images/${f[0].id}/remove`);
    check("a player cannot confirm removal", res.status === 403);
    res = await call("mod", "POST", `/v1/curation/images/${f[0].id}/remove`);
    check("removal rejects and locks the frame", res.status === 200 && res.body.removedAt > 0 && res.body.status === "rejected"
        && row("movie_7777").missing_images === 0, JSON.stringify(res.body));
    await call("mod", "POST", "/v1/catalog/items/movie_7777/reset");
    check("a reset does not bring a removed frame back", frame(f[0].id).status === "rejected" && frame(f[0].id).moderator_status === "rejected");
    await call("mod", "POST", "/v1/curation/titles/movie_7777/verdicts", { verdicts: f.slice(1, 8).map((x) => ({ imageId: x.id, status: "approved", difficultyTier: "hard" }))
        .concat([{ imageId: f[0].id, status: "approved", difficultyTier: "easy" }]), rejectRemaining: true });
    check("nor does a verdict", frame(f[0].id).status === "rejected");

    db.db.prepare("UPDATE media_images SET missing_at = 5 WHERE id IN (?, ?)").run(f[3].id, f[4].id);
    await refreshMediaCounters({ DB: db }, "movie_7777");
    check("fewer than six in play takes the title out", row("movie_7777").approved_images === 5 && row("movie_7777").published === 0);
    res = await call("mod", "POST", `/v1/curation/images/${f[3].id}/restore`);
    check("restoring a frame puts it back", res.status === 200 && res.body.missingAt === null && row("movie_7777").approved_images === 6
        && row("movie_7777").published === 1, JSON.stringify(res.body));
}

console.log("random and automatic dailies");
{
    const today = new Date().toISOString().slice(0, 10);
    const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
    const later = new Date(Date.now() + 5 * 86400000).toISOString().slice(0, 10);
    db.db.prepare("DELETE FROM daily_overrides WHERE date >= ?").run(today);
    db.db.prepare("INSERT INTO daily_overrides (date, media_key, created_at) VALUES ('2000-01-01', 'movie_102', 0)").run();
    const eligible = db.db.prepare(
        "SELECT key FROM media_items WHERE media_type = 'movie' AND published = 1 AND approved_images >= 7 AND key != 'movie_102'"
    ).all().map((r) => r.key);
    const dayRow = (date) => db.db.prepare("SELECT * FROM daily_overrides WHERE date = ?").get(date);

    check("off by default, the cron leaves tomorrow empty", (await autoScheduleTomorrow(env)) === null && !dayRow(tomorrow));

    res = await call("mod", "PUT", `/v1/admin/daily/${later}`, { random: true });
    check("a moderator can roll a random film for a day", res.status === 200 && eligible.includes(res.body.mediaKey)
        && res.body.frameIds.length === 6 && dayRow(later).created_by === "mod", JSON.stringify(res.body));
    res = await call("plain", "PUT", `/v1/admin/daily/${later}`, { random: true });
    check("a player cannot", res.status === 403);

    await call("me", "PATCH", "/v1/admin/config", { autoDaily: true });
    const outcome = await autoScheduleTomorrow(env);
    check("with the toggle on, tomorrow gets a film", outcome?.date === tomorrow && dayRow(tomorrow)?.created_by === "auto"
        && JSON.parse(dayRow(tomorrow).frame_ids).length === 6, JSON.stringify(outcome));
    check("an unused one", eligible.includes(dayRow(tomorrow).media_key) && dayRow(tomorrow).media_key !== dayRow(later).media_key);
    check("today is never filled behind a moderator's back", !dayRow(today));
    check("a filled tomorrow is left alone", (await autoScheduleTomorrow(env)) === null);
    res = await call("mod", "GET", "/v1/admin/daily?limit=10");
    check("the schedule says which were automatic", res.body.schedule.find((d) => d.date === tomorrow)?.autoPicked === true
        && res.body.schedule.find((d) => d.date === later)?.autoPicked === false);

    db.db.prepare("DELETE FROM daily_overrides WHERE date >= ?").run(today);
    const keep = eligible.map((key) => `'${key}'`).join(",");
    db.db.prepare(`INSERT INTO daily_overrides (date, media_key, created_at) SELECT '1999-01-' || printf('%02d', rowid % 28 + 1) || '-' || key, key, 0 FROM media_items WHERE key IN (${keep})`).run();
    res = await call("mod", "PUT", `/v1/admin/daily/${later}`, { random: true });
    check("when every film has had its day, a roll says so", res.status === 409, JSON.stringify(res.body));
    check("and the cron stays quiet", (await autoScheduleTomorrow(env)) === null);
    db.db.prepare("DELETE FROM daily_overrides WHERE date < '2000-01-02' OR date >= ?").run(today);
    await call("me", "PATCH", "/v1/admin/config", { autoDaily: false });
}

console.log("playlists count what can be played");
{
    const pl = await call("mod", "POST", "/v1/playlists", { title: "Пропуски", mediaType: "movie" });
    await call("mod", "PUT", `/v1/playlists/${pl.body.id}/items`, { mediaKeys: ["movie_101", "movie_102", "movie_7777"] });
    res = await call("mod", "GET", `/v1/round/next?playlistId=${pl.body.id}`);
    check("an unplayable entry is skipped and not counted", res.status === 200 && res.body.item.key === "movie_102"
        && res.body.position === 1 && res.body.playlistTotal === 2, JSON.stringify(res.body).slice(0, 200));
    await call("mod", "POST", "/v1/round/finish", { mediaKey: "movie_102", mode: "playlist", playlistId: pl.body.id, result: "wrong", frameCount: 6 });
    res = await call("mod", "GET", `/v1/round/next?playlistId=${pl.body.id}`);
    check("positions are among the playable", res.body.item.key === "movie_7777" && res.body.position === 2 && res.body.playlistTotal === 2);
    res = await call("mod", "GET", `/v1/playlists/${pl.body.id}`);
    check("progress counts the playable", res.body.progress.total === 2 && res.body.progress.answered === 1
        && res.body.items.find((i) => i.key === "movie_101").playable === false, JSON.stringify(res.body.progress));
    db.db.prepare("UPDATE media_items SET published = 0 WHERE key = 'movie_102'").run();
    res = await call("mod", "GET", `/v1/playlists/${pl.body.id}`);
    check("an answered title that leaves the game leaves the count", res.body.progress.total === 1 && res.body.progress.answered === 0);
    await refreshMediaCounters({ DB: db }, "movie_102");
    db.db.prepare("UPDATE media_items SET published = 1 WHERE key = 'movie_102'").run();
}

// ------------------------------------------------------------------ refresh sessions

console.log("refresh sessions");
{
    const post = async (path, body) => {
        const response = await worker.fetch(new Request(`https://api.test${path}`, {
            method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body)
        }), env, {});
        return { status: response.status, body: await response.json().catch(() => null) };
    };
    const refresh = (token) => post("/v1/auth/refresh", { refreshToken: token });
    const sessionsOf = (uid) => db.db.prepare("SELECT * FROM refresh_sessions WHERE uid = ?").all(uid);

    const signIn = await post("/v1/auth/anonymous", { deviceSecret: "s".repeat(43) });
    const uid = signIn.body.user.uid;
    check("sign-in opens a session", signIn.status === 200 && /^[0-9a-f-]{36}\.0\.[A-Za-z0-9_-]{43}$/.test(signIn.body.refreshToken)
        && sessionsOf(uid).length === 1, signIn.body.refreshToken);
    check("the table holds nothing to sign in with", !JSON.stringify(sessionsOf(uid)).includes(signIn.body.refreshToken.split(".")[2]));

    let token = signIn.body.refreshToken;
    const history = [token];
    for (let i = 0; i < 20; i += 1) {
        const next = await refresh(token);
        if (next.status !== 200) break;
        token = next.body.refreshToken;
        history.push(token);
    }
    check("twenty rotations, still one row", history.length === 21 && sessionsOf(uid).length === 1 && sessionsOf(uid)[0].generation === 20);

    const retried = await refresh(history[19]);
    check("the previous token, retried at once, gets the same successor", retried.status === 200 && retried.body.refreshToken === token);
    const racing = await Promise.all([refresh(token), refresh(token)]);
    check("two racing refreshes both succeed with one successor", racing.every((r) => r.status === 200)
        && racing[0].body.refreshToken === racing[1].body.refreshToken, JSON.stringify(racing.map((r) => r.status)));
    token = racing[0].body.refreshToken;

    const [id, generation] = token.split(".");
    res = await refresh(`${id}.${generation}.${"A".repeat(43)}`);
    check("a forged token naming the session is unknown and harmless", res.status === 401 && sessionsOf(uid)[0].revoked_at === null);

    db.db.prepare("UPDATE refresh_sessions SET rotated_at = ? WHERE uid = ?").run(Date.now() - REFRESH_RETRY_GRACE_MS - 1000, uid);
    const second = await post("/v1/auth/anonymous", { deviceSecret: "s".repeat(43) });
    res = await refresh(history[19]);
    check("an old token after the grace is a replay", res.status === 401 && res.body.message.includes("already used"));
    check("and every session of the account goes", sessionsOf(uid).every((row) => row.revoked_at !== null) && sessionsOf(uid).length === 2);
    res = await refresh(token);
    check("the current token is revoked with them", res.status === 401 && res.body.message.includes("revoked"));
    res = await refresh(second.body.refreshToken);
    check("so is the other device's", res.status === 401);

    res = await refresh("1z3nd66Vxk2TYd56Tiv6StDKpQm3ldufT-4YjPv175Q");
    check("a token in the old format is unknown, and the app signs in again", res.status === 401 && res.body.message.includes("Unknown"));

    const third = await post("/v1/auth/anonymous", { deviceSecret: "s".repeat(43) });
    const access = third.body.accessToken;
    await worker.fetch(new Request("https://api.test/v1/auth/logout", { method: "POST", headers: { Authorization: `Bearer ${access}` } }), env, {});
    check("logout revokes the sessions", (await refresh(third.body.refreshToken)).status === 401);

    db.db.prepare("UPDATE refresh_sessions SET expires_at = 1 WHERE uid = ? AND revoked_at IS NULL").run(uid);
    db.db.prepare("UPDATE refresh_sessions SET revoked_at = 1 WHERE uid = ? AND revoked_at IS NOT NULL").run(uid);
    const live = await post("/v1/auth/anonymous", { deviceSecret: "s".repeat(43) });
    await worker.scheduled({ cron: NIGHTLY_CRON, scheduledTime: Date.now() }, env, {});
    check("the nightly run drops expired and long-revoked sessions", sessionsOf(uid).length === 1
        && (await refresh(live.body.refreshToken)).status === 200);
    db.db.prepare("DELETE FROM users WHERE uid = ?").run(uid);
}

// ------------------------------------------------------------------ deletion

console.log("account deletion");
const target = db.db.prepare("SELECT id FROM media_images WHERE media_key = 'movie_103' AND moderator_status IS NULL AND status = 'pending' LIMIT 1").get();
db.db.prepare("UPDATE users SET report_multiplier = 5 WHERE uid = 'plain'").run();
res = await call("plain", "POST", "/v1/curation/report", { imageId: target.id, reason: "not_a_frame" });
check("a heavy report hides the frame", res.status === 200 && db.db.prepare("SELECT status FROM media_images WHERE id = ?").get(target.id).status === "rejected", JSON.stringify(res));
db.db.prepare("INSERT INTO refresh_sessions (id, uid, salt, created_at, expires_at) VALUES ('s-plain', 'plain', 'x', 0, 9999999999999)").run();
res = await call("plain", "DELETE", "/v1/profile");
const left = (table) => db.db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE uid = 'plain'`).get().n;
check("delete answers 204", res.status === 204, JSON.stringify(res));
check("user, tokens, watched and reports are gone", left("users") + left("refresh_sessions") + left("watched_media") + left("image_reports") === 0);
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
    reporterBar: ["SELECT COUNT(*) AS count FROM (SELECT 1 FROM watched_media WHERE uid = ? LIMIT ?)", ["plain", 5]],
    syncDue: [`SELECT * FROM media_items INDEXED BY idx_media_synced
               WHERE last_synced_at < ?1 AND (last_synced_at < ?2 OR release_year >= ?3)
               ORDER BY last_synced_at LIMIT ?4`, [1, 0, 2025, 2]],
    unrated: ["SELECT key, media_type, tmdb_id FROM media_items WHERE vote_count IS NULL LIMIT ?", [5]],
    missingBadge: ["SELECT COUNT(*) AS n FROM media_items WHERE missing_images > 0", []],
    titleStats: [`SELECT solved_at_frame AS frame, COUNT(*) AS n FROM watched_media
                  WHERE media_key = ? AND result IS NOT NULL GROUP BY solved_at_frame`, ["movie_101"]],
    dayStats: [`SELECT CASE WHEN was_correct = 1 THEN attempts_used END AS frame, COUNT(*) AS n
                FROM daily_results WHERE date = ? GROUP BY was_correct, attempts_used`, ["2026-01-01"]]
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
    const sorts = /TEMP B-TREE FOR (ORDER|GROUP) BY/.test(text);
    const scansPlayers = /SCAN (watched_media|daily_results)\b/.test(text);
    const fullItems = /SCAN m\b(?! USING)/.test(text) || /SCAN media_items\b(?! USING)/.test(text);
    check(`${name}: no frame scan, no sort, no bare table scan`, !scansFrames && !sorts && !fullItems && !scansPlayers, `\n      ${text}`);
}

console.log(failures ? `\n${failures} FAILED` : "\nall passed");
process.exit(failures ? 1 : 0);
