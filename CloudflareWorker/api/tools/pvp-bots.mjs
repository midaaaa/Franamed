// Bots that play a whole PvP match: sign in, create or join a room, load
// frames and press ready, answer with delays, drop off the network and come
// back. With no phone to test on, this is the check of the real-time side.
//
//   node --no-warnings tools/pvp-bots.mjs --local                 in-process, virtual clock
//   node --no-warnings tools/pvp-bots.mjs --url http://127.0.0.1:8787 --db <wrangler sqlite>
//   node --no-warnings tools/pvp-bots.mjs --seed-sql > pvp-seed.sql
//
// Options: --kind room|duel (room), --players N (4; a duel is always 2),
// --films 5|10|15 (5), --time 30|45|60 (30), --accuracy 0..1 (0.5),
// --drop [seconds] (one player goes silent on the second film and returns,
// 20 s by default; past 60 s a duel is forfeited), --seed N.
//
// A bot knows the answer the way docs/pvp.md §14 says anyone can: it looks the
// frame's file path up in the catalogue. Locally that is the test database; for
// wrangler dev it is wrangler's own SQLite file (--db).
//
// Run from CloudflareWorker/api. See docs/pvp.md for the wrangler dev steps.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

const API = new URL("..", import.meta.url).pathname;

// ------------------------------------------------------------------ catalogue

// Published films with nine approved frames each, three per tier. Plain
// INSERTs, one per row: D1 refuses long compound statements.
export function seedStatements(count = 24) {
    const statements = [];
    let image = 900000;
    for (let i = 0; i < count; i += 1) {
        const tmdbId = 70000 + i;
        const key = `movie_${tmdbId}`;
        statements.push(
            `INSERT OR IGNORE INTO media_items (key, tmdb_id, media_type, title, original_title, release_year, popularity, poster_url, status, approved_images, reviewed_images, total_images, published, created_at, shuffle_key)
             VALUES ('${key}', ${tmdbId}, 'movie', 'Bot Film ${i + 1}', 'Bot Film ${i + 1}', ${1970 + i}, ${100 - i}, '/poster-${tmdbId}.jpg', 'approved', 9, 9, 9, 1, 0, ${((i * 0.6180339887) % 1).toFixed(6)});`
        );
        for (let f = 0; f < 9; f += 1) {
            image += 1;
            statements.push(
                `INSERT OR IGNORE INTO media_images (id, media_key, file_path, status, difficulty_tier, moderator_status, width, height, created_at)
                 VALUES (${image}, '${key}', '/bot-${tmdbId}-${f}.jpg', 'approved', '${["hard", "medium", "easy"][f % 3]}', 'approved', 1920, 1080, 0);`
            );
        }
    }
    return statements;
}

export function oracleFrom(query) {
    return (path) => query(path) ?? null;
}

// ------------------------------------------------------------------ scheduling

// Virtual time: the loop jumps the clock to the next thing due, a bot's delay
// or a room's alarm, so a ten-minute match runs in well under a second.
export class VirtualLoop {
    tasks = [];
    nextId = 1;

    constructor(clock, namespace) {
        this.clock = clock;
        this.namespace = namespace;
    }

    after(ms, work) {
        const id = this.nextId++;
        this.tasks.push({ id, at: this.clock.now() + Math.max(0, ms), work });
        return id;
    }

    cancel(id) {
        this.tasks = this.tasks.filter((task) => task.id !== id);
    }

    async run({ until, limitMs = 60 * 60 * 1000 }) {
        const end = this.clock.now() + limitMs;
        while (!until()) {
            await this.namespace.settle();
            if (until()) break;
            const alarm = this.namespace.nextAlarm();
            const task = this.tasks.reduce((best, item) => (!best || item.at < best.at ? item : best), null);
            const next = Math.min(task?.at ?? Infinity, alarm ?? Infinity);
            if (next === Infinity || next > end) break;
            this.clock.time = Math.max(this.clock.time, next);

            const due = this.tasks.filter((item) => item.at <= this.clock.time).sort((a, b) => a.at - b.at || a.id - b.id);
            this.tasks = this.tasks.filter((item) => item.at > this.clock.time);
            for (const item of due) {
                await item.work();
                await this.namespace.settle();
            }
            await this.namespace.fireAlarms();
        }
    }
}

export class RealLoop {
    timers = new Map();
    nextId = 1;

    after(ms, work) {
        const id = this.nextId++;
        this.timers.set(id, setTimeout(() => {
            this.timers.delete(id);
            work();
        }, Math.max(0, ms)));
        return id;
    }

    cancel(id) {
        clearTimeout(this.timers.get(id));
        this.timers.delete(id);
    }

    async run({ until, limitMs = 15 * 60 * 1000 }) {
        const end = Date.now() + limitMs;
        while (!until() && Date.now() < end) await new Promise((resolve) => setTimeout(resolve, 100));
    }
}

// ------------------------------------------------------------------ transport

export class LocalApi {
    constructor({ worker, env, namespace }) {
        this.worker = worker;
        this.env = env;
        this.namespace = namespace;
    }

    async request(method, path, body, token, ip = "10.0.0.1") {
        const headers = { "Content-Type": "application/json", "CF-Connecting-IP": ip };
        if (token) headers.Authorization = `Bearer ${token}`;
        const response = await this.worker.fetch(
            new Request(`https://api.test${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }),
            this.env,
            { waitUntil() {} }
        );
        await this.namespace.settle();
        return { status: response.status, body: await response.json().catch(() => null) };
    }

    async socket(code, token, lastSeq) {
        const response = await this.worker.fetch(
            new Request(`https://api.test/v1/pvp/rooms/${code}/ws?lastSeq=${lastSeq ?? ""}`, {
                headers: { Upgrade: "websocket", Authorization: `PvP ${token}` }
            }),
            this.env,
            { waitUntil() {} }
        );
        if (response.status !== 101) return { error: (await response.json().catch(() => ({}))).error || response.status };
        const client = response.webSocket;
        return {
            send: (msg) => client.send(typeof msg === "string" ? msg : JSON.stringify(msg)),
            close: () => client.close(1000),
            vanish: () => client.vanish(),
            set onmessage(handler) { client.onmessage = handler; },
            set onclose(handler) { client.onclose = handler; }
        };
    }
}

export class RemoteApi {
    constructor(base) {
        this.base = base.replace(/\/$/, "");
    }

    async request(method, path, body, token) {
        const headers = { "Content-Type": "application/json" };
        if (token) headers.Authorization = `Bearer ${token}`;
        const response = await fetch(`${this.base}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
        return { status: response.status, body: await response.json().catch(() => null) };
    }

    async socket(code, token, lastSeq) {
        const url = `${this.base.replace(/^http/, "ws")}/v1/pvp/rooms/${code}/ws?lastSeq=${lastSeq ?? ""}`;
        const ws = new WebSocket(url, { headers: { Authorization: `PvP ${token}` } });
        let onmessage = null;
        let onclose = null;
        let vanished = false;
        const held = [];
        ws.onmessage = (event) => {
            if (vanished) return;
            if (onmessage) onmessage(String(event.data));
            else held.push(String(event.data));
        };
        ws.onclose = (event) => onclose?.({ code: event.code, reason: event.reason });
        const opened = await new Promise((resolve) => {
            ws.onopen = () => resolve(true);
            ws.onerror = () => resolve(false);
        });
        if (!opened) return { error: "connect_failed" };
        return {
            send: (msg) => !vanished && ws.readyState === 1 && ws.send(typeof msg === "string" ? msg : JSON.stringify(msg)),
            close: () => ws.close(1000),
            // A real socket cannot be made to vanish; it goes quiet instead and
            // the room has to notice the silence on its own.
            vanish: () => { vanished = true; },
            set onmessage(handler) {
                onmessage = handler;
                for (const text of held.splice(0)) handler(text);
            },
            set onclose(handler) { onclose = handler; }
        };
    }
}

// ------------------------------------------------------------------ bot

export class Bot {
    constructor({ name, api, loop, oracle, random, accuracy = 0.5, think = [1500, 6000], log = () => {} }) {
        Object.assign(this, { name, api, loop, oracle, random, accuracy, think, log });
        this.seq = -1;
        this.snapshotSeq = -1;
        this.frames = {};
        this.mine = null;
        this.reveals = [];
        this.errors = [];
        this.finished = null;
        this.closedWith = null;
        this.offline = false;
        this.timers = new Set();
        this.guesses = 0;
    }

    delay([min, max]) {
        return min + Math.floor(this.random() * (max - min));
    }

    later(ms, work) {
        const id = this.loop.after(ms, () => {
            this.timers.delete(id);
            return work();
        });
        this.timers.add(id);
    }

    stop() {
        for (const id of this.timers) this.loop.cancel(id);
        this.timers.clear();
        this.stopped = true;
    }

    async signIn() {
        const secret = `${this.name}-${Math.floor(this.random() * 1e12)}`.padEnd(43, "x");
        const response = await this.api.request("POST", "/v1/auth/anonymous", { deviceSecret: secret });
        if (response.status !== 200) throw new Error(`${this.name}: sign-in ${response.status} ${JSON.stringify(response.body)}`);
        this.token = response.body.accessToken;
        this.uid = response.body.user.uid;
        const named = await this.api.request("PATCH", "/v1/pvp/profile", { name: this.name }, this.token);
        this.profile = named.body;
    }

    async create(settings) {
        const response = await this.api.request("POST", "/v1/pvp/rooms", settings, this.token);
        if (response.status !== 201) throw new Error(`${this.name}: create ${response.status} ${JSON.stringify(response.body)}`);
        this.code = response.body.code;
        return this.connect(response.body.ticket);
    }

    async join(code) {
        this.code = code;
        const response = await this.api.request("POST", `/v1/pvp/rooms/${code}/ticket`, undefined, this.token);
        if (response.status !== 200) throw new Error(`${this.name}: ticket ${response.status} ${JSON.stringify(response.body)}`);
        return this.connect(response.body.ticket);
    }

    async connect(token) {
        const socket = await this.api.socket(this.code, token, this.seq);
        if (socket.error) throw new Error(`${this.name}: socket ${socket.error}`);
        this.socket = socket;
        this.offline = false;
        socket.onmessage = (text) => this.receive(JSON.parse(text));
        socket.onclose = ({ code }) => {
            if (this.socket === socket) this.closedWith = code;
        };
        this.pinging();
    }

    pinging() {
        this.later(10000, () => {
            if (this.stopped || this.offline) return;
            this.socket?.send('{"t":"ping"}');
            this.pinging();
        });
    }

    send(msg) {
        if (!this.offline) this.socket.send(msg);
    }

    // Gone without a word, back after `ms` with the resume token.
    dropFor(ms) {
        this.log(`${this.name} drops off for ${ms / 1000}s`);
        this.offline = true;
        this.socket.vanish();
        this.later(ms, async () => {
            this.log(`${this.name} comes back`);
            await this.connect(this.resumeToken);
        });
    }

    receive(msg) {
        if (msg.t === "pong") return;
        // One step of the room can send several messages under one seq; only
        // what is older than the last snapshot is already in it.
        if (msg.seq !== undefined && msg.seq < this.snapshotSeq) return;
        if (msg.seq !== undefined) this.seq = Math.max(this.seq, msg.seq);

        switch (msg.t) {
            case "welcome":
                this.resumeToken = msg.you.resumeToken;
                if (msg.snapshot) this.apply(msg.snapshot);
                break;
            case "snapshot":
                this.apply(msg);
                break;
            case "prepare":
                this.prepare(msg);
                break;
            case "countdown":
                if (msg.participants.includes(this.uid)) {
                    this.mine = { film: msg.film, frame: 1, status: "thinking" };
                    this.later(msg.startsInMs + this.delay(this.think), () => this.answer());
                } else {
                    this.mine = null;
                }
                break;
            case "guessResult":
                if (this.mine && msg.film === this.mine.film) {
                    if (msg.correct) this.mine.status = "solved";
                }
                break;
            case "progress":
                if (msg.uid === this.uid && this.mine && msg.film === this.mine.film) {
                    this.mine.frame = msg.frame;
                    this.mine.status = msg.status;
                    if (msg.status === "thinking") this.later(this.delay(this.think), () => this.answer());
                }
                break;
            case "reveal":
                this.reveals.push(msg);
                this.mine = null;
                break;
            case "finished":
                this.finished = msg;
                break;
            case "error":
                this.errors.push(msg.code);
                break;
            default:
                break;
        }
    }

    apply(snapshot) {
        this.snapshot = snapshot;
        this.snapshotSeq = snapshot.seq;
        if (snapshot.finished) this.finished = snapshot.finished;
        if (snapshot.prepare && !snapshot.prepare.ready) this.prepare(snapshot.prepare);
        const film = snapshot.film;
        if (film?.frames) {
            this.frames[film.index] = film.frames;
            this.mine = { film: film.index, frame: film.yourFrame, status: film.yourStatus };
            if (film.yourStatus === "thinking") this.later(film.startsInMs + this.delay(this.think), () => this.answer());
        } else if (film) {
            this.mine = null;
        }
    }

    prepare(msg) {
        this.frames[msg.film] = msg.frames;
        // Downloading the frames, then ready.
        this.later(this.delay([200, 1500]), () => this.send({ t: "ready", film: msg.film }));
    }

    answer() {
        const mine = this.mine;
        if (!mine || mine.status !== "thinking" || this.offline || this.stopped) return;
        const frames = this.frames[mine.film];
        const knows = this.random() < Math.min(1, this.accuracy + (mine.frame - 1) * 0.1);
        this.guesses += 1;
        if (knows && frames) {
            const answer = this.oracle(frames[0].path);
            this.send({ t: "guess", film: mine.film, frame: mine.frame, tmdbId: answer.tmdbId, mediaType: answer.mediaType });
        } else if (this.random() < 0.25) {
            this.send({ t: "skip", film: mine.film, frame: mine.frame });
        } else {
            this.send({ t: "guess", film: mine.film, frame: mine.frame, tmdbId: -1, mediaType: "movie" });
        }
        // The next step waits for the progress message.
        mine.status = "waiting";
    }
}

// ------------------------------------------------------------------ local

export async function localServer({ films = 24 } = {}) {
    const { D1 } = await import("../test/d1.mjs");
    const { Clock, Namespace } = await import("../test/pvp-shim.mjs");
    const { default: worker } = await import(`${API}src/index.js`);

    const clock = new Clock(Date.now());
    const db = new D1();
    db.exec(readFileSync(`${API}schema.sql`, "utf8"));
    for (const statement of seedStatements(films)) db.exec(statement);

    const namespace = new Namespace(clock);
    const env = { DB: db, JWT_SECRET: "bot-secret-bot-secret-bot-secret-0000", PVP_ROOM: namespace, PVP_NOW: clock.now };
    namespace.bind(env);

    const oracle = oracleFrom((path) => db.db.prepare(
        "SELECT m.tmdb_id AS tmdbId, m.media_type AS mediaType FROM media_images i JOIN media_items m ON m.key = i.media_key WHERE i.file_path = ?"
    ).get(path));

    return { clock, db, namespace, env, worker, oracle, api: new LocalApi({ worker, env, namespace }), loop: new VirtualLoop(clock, namespace) };
}

// ------------------------------------------------------------------ scenario

export async function playMatch({ api, loop, oracle, random, kind = "room", players = 4, films = 5, time = 30, accuracy = 0.5, drop = false, dropMs = 20000, log = () => {} }) {
    const count = kind === "duel" ? 2 : players;
    const names = ["NoirGaffer", "SilentFoley", "MidnightReel", "VelvetCameo", "NeonUsher", "RetroSlate", "CultEditor", "LostTakes"];
    const bots = names.slice(0, count).map((name) => new Bot({ name, api, loop, oracle, random, accuracy, log }));

    for (const bot of bots) await bot.signIn();
    await bots[0].create({ kind, mediaType: "movie", ...(kind === "room" ? { films } : {}), timeLimitSec: time });
    log(`room ${bots[0].code} (${kind}) created by ${bots[0].name}`);
    for (const bot of bots.slice(1)) await bot.join(bots[0].code);

    if (kind === "room") {
        loop.after(500, () => bots[0].send({ t: "start" }));
    } else {
        for (const bot of bots) loop.after(300, () => bot.send({ t: "ready", film: 0 }));
    }

    if (drop) {
        // The last player goes silent on the second film and returns later.
        const victim = bots[count - 1];
        const watch = () => {
            if (victim.mine?.film === 2 && victim.mine.status !== "solved") victim.dropFor(dropMs);
            else if (!victim.finished && !victim.stopped) loop.after(1000, watch);
        };
        loop.after(1000, watch);
    }

    await loop.run({ until: () => bots.every((bot) => bot.finished) });
    for (const bot of bots) bot.stop();
    return bots;
}

function report(bots, log) {
    const finished = bots[0].finished;
    if (!finished) {
        log("match did not finish");
        return false;
    }
    const nameOf = (uid) => bots.find((bot) => bot.uid === uid)?.name ?? uid;
    log(`finished: ${finished.reason}${finished.winnerUid ? `, winner ${nameOf(finished.winnerUid)}` : ""}`);
    for (const row of finished.standings) {
        log(`  ${row.place}. ${nameOf(row.uid).padEnd(14)} ${row.total !== undefined ? `${row.total} pts` : `${row.hp} hp`}`);
    }
    for (const film of finished.films) {
        const line = film.results.map((r) => `${nameOf(r.uid)}:${r.solvedAtFrame ? `f${r.solvedAtFrame}/${(r.ms / 1000).toFixed(1)}s/${r.points}` : "—"}`).join("  ");
        log(`  film ${film.film} ${film.answer.title.padEnd(12)} ${line}`);
    }
    const errors = bots.flatMap((bot) => bot.errors.map((code) => `${bot.name}:${code}`));
    if (errors.length) log(`errors: ${errors.join(", ")}`);
    return true;
}

// ------------------------------------------------------------------ cli

function option(name, fallback) {
    const index = process.argv.indexOf(`--${name}`);
    if (index === -1) return fallback;
    const value = process.argv[index + 1];
    return value === undefined || value.startsWith("--") ? true : value;
}

function findWranglerDatabase() {
    const dir = join(API, ".wrangler/state/v3/d1/miniflare-D1DatabaseObject");
    if (!existsSync(dir)) return null;
    const file = readdirSync(dir).find((name) => name.endsWith(".sqlite"));
    return file ? join(dir, file) : null;
}

if (import.meta.url === `file://${process.argv[1]}`) {
    const { seededRandom } = await import(`${API}src/lib/frames.js`);
    const random = seededRandom(Number(option("seed", 1)));
    const log = (line) => console.log(line);
    const settings = {
        kind: option("kind", "room"),
        players: Number(option("players", 4)),
        films: Number(option("films", 5)),
        time: Number(option("time", 30)),
        accuracy: Number(option("accuracy", 0.5)),
        drop: Boolean(option("drop", false)),
        dropMs: (Number(option("drop", 20)) || 20) * 1000
    };

    if (option("seed-sql", false)) {
        console.log(seedStatements().join("\n"));
    } else if (option("local", false)) {
        const server = await localServer();
        const started = server.clock.now();
        const bots = await playMatch({ ...settings, api: server.api, loop: server.loop, oracle: server.oracle, random, log: (line) => log(`[${((server.clock.now() - started) / 1000).toFixed(1).padStart(6)}s] ${line}`) });
        const ok = report(bots, log);
        for (const [code, object] of server.namespace.objects) {
            log(`room ${code}: ${object.requests} requests, ${object.messages} socket messages (≈${Math.ceil(object.messages / 20)} billed), ${object.alarms} alarms, ${object.storage.writes} storage writes`);
        }
        process.exit(ok ? 0 : 1);
    } else {
        const url = option("url", "http://127.0.0.1:8787");
        const path = option("db", null) || findWranglerDatabase();
        if (!path) {
            console.error("No wrangler database found: pass --db <path to .sqlite under .wrangler/state>");
            process.exit(2);
        }
        const db = new DatabaseSync(path, { readOnly: true });
        const oracle = oracleFrom((framePath) => db.prepare(
            "SELECT m.tmdb_id AS tmdbId, m.media_type AS mediaType FROM media_images i JOIN media_items m ON m.key = i.media_key WHERE i.file_path = ?"
        ).get(framePath));
        const started = Date.now();
        const bots = await playMatch({ ...settings, api: new RemoteApi(url), loop: new RealLoop(), oracle, random, log: (line) => log(`[${((Date.now() - started) / 1000).toFixed(1).padStart(6)}s] ${line}`) });
        process.exit(report(bots, log) ? 0 : 1);
    }
}
