// The real worker (CloudflareWorker/api) behind a real HTTP and WebSocket
// server on localhost, with the test shims for D1 and the room object and a
// wall clock. Swift tests start it, point the client at it and break things
// through /__control: drop or close sockets, refuse upgrades, run bots.
//
//   node --no-warnings Tools/PvPKit/Server/pvp-server.mjs [--port 0] [--config '{"pvpRevealSec":2}']
//
// Prints {"port": N} on the first line of stdout once it listens.

import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const API = new URL("../../../CloudflareWorker/api/", import.meta.url).pathname;
const { D1 } = await import(`${API}test/d1.mjs`);
const { Namespace } = await import(`${API}test/pvp-shim.mjs`);
const { default: worker } = await import(`${API}src/index.js`);
const { Bot, LocalApi, RealLoop, seedStatements, oracleFrom } = await import(`${API}tools/pvp-bots.mjs`);
const { seededRandom } = await import(`${API}src/lib/frames.js`);

function option(name, fallback) {
    const index = process.argv.indexOf(`--${name}`);
    return index === -1 ? fallback : process.argv[index + 1];
}

const clock = { now: () => Date.now() };
const db = new D1();
db.exec(readFileSync(`${API}schema.sql`, "utf8"));
for (const statement of seedStatements(24)) db.exec(statement);
for (const [key, value] of Object.entries(JSON.parse(option("config", "{}")))) {
    db.exec(`INSERT INTO app_config (key, value) VALUES ('${key}', '${value}') ON CONFLICT (key) DO UPDATE SET value = excluded.value`);
}

const namespace = new Namespace(clock);
const env = { DB: db, JWT_SECRET: "fake-server-secret-fake-server-secret-00", PVP_ROOM: namespace, PVP_NOW: clock.now };
namespace.bind(env);
const oracle = oracleFrom((path) => db.db.prepare(
    "SELECT m.tmdb_id AS tmdbId, m.media_type AS mediaType FROM media_images i JOIN media_items m ON m.key = i.media_key WHERE i.file_path = ?"
).get(path));

setInterval(() => {
    const due = namespace.nextAlarm();
    if (due !== null && due <= clock.now()) namespace.fireAlarms();
}, 20);

// ------------------------------------------------------------------ bookkeeping

const control = { refuseSockets: 0, refusePolls: 0, silentPolls: 0 };
const received = new Map();
const connections = new Map();
const stats = new Map();

function stat(uid) {
    if (!stats.has(uid)) stats.set(uid, { sockets: 0, socketsRefused: 0, polls: 0, pollsRefused: 0 });
    return stats.get(uid);
}

function uidOf(token) {
    try {
        return JSON.parse(Buffer.from(String(token).split(".")[1], "base64url").toString()).uid ?? null;
    } catch {
        return null;
    }
}

function record(uid, via, text) {
    if (!uid) return;
    if (!received.has(uid)) received.set(uid, []);
    received.get(uid).push({ at: clock.now(), via, text });
}

// ------------------------------------------------------------------ websocket

function frame(opcode, payload) {
    const length = payload.length;
    const head = length < 126 ? Buffer.from([0x80 | opcode, length])
        : length < 65536 ? Buffer.from([0x80 | opcode, 126, length >> 8, length & 255])
        : Buffer.concat([Buffer.from([0x80 | opcode, 127]), (() => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(length)); return b; })()]);
    return Buffer.concat([head, payload]);
}

function closeFrame(code, reason) {
    const payload = Buffer.alloc(2 + Buffer.byteLength(reason));
    payload.writeUInt16BE(code, 0);
    payload.write(reason, 2);
    return frame(8, payload);
}

function readFrames(state, chunk, onFrame) {
    state.buffer = Buffer.concat([state.buffer, chunk]);
    for (;;) {
        const b = state.buffer;
        if (b.length < 2) return;
        const opcode = b[0] & 15;
        const masked = (b[1] & 128) !== 0;
        let length = b[1] & 127;
        let offset = 2;
        if (length === 126) {
            if (b.length < 4) return;
            length = b.readUInt16BE(2);
            offset = 4;
        } else if (length === 127) {
            if (b.length < 10) return;
            length = Number(b.readBigUInt64BE(2));
            offset = 10;
        }
        const maskAt = offset;
        if (masked) offset += 4;
        if (b.length < offset + length) return;
        const payload = Buffer.from(b.subarray(offset, offset + length));
        if (masked) for (let i = 0; i < payload.length; i += 1) payload[i] ^= b[maskAt + (i % 4)];
        state.buffer = b.subarray(offset + length);
        onFrame(opcode, payload, (b[0] & 128) !== 0);
    }
}

async function upgrade(request, socket) {
    const url = new URL(request.url, "http://localhost");
    const token = String(request.headers.authorization || "").replace(/^PvP\s+/, "");
    const tokenUid = uidOf(token);
    if (control.refuseSockets > 0) {
        control.refuseSockets -= 1;
        if (tokenUid) stat(tokenUid).socketsRefused += 1;
        socket.end("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    }

    const response = await worker.fetch(
        new Request(`http://${request.headers.host}${url.pathname}${url.search}`, { headers: { Upgrade: "websocket", Authorization: request.headers.authorization || "" } }),
        env,
        { waitUntil() {} }
    );
    await namespace.settle();
    if (response.status !== 101) {
        const body = await response.text();
        socket.end(`HTTP/1.1 ${response.status} Refused\r\nContent-Type: application/json\r\nContent-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`);
        return;
    }

    const accept = createHash("sha1").update(`${request.headers["sec-websocket-key"]}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest("base64");
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    socket.setNoDelay(true);

    const client = response.webSocket;
    const link = { uid: tokenUid, socket, client, open: true };
    if (tokenUid) stat(tokenUid).sockets += 1;

    client.onmessage = (text) => {
        if (!link.open || link.muted) return;
        try {
            const msg = JSON.parse(text);
            if (msg.t === "welcome") {
                link.uid = msg.you.uid;
                connections.set(link.uid, link);
            }
        } catch {
            // Not JSON: passed on as it is.
        }
        socket.write(frame(1, Buffer.from(text)));
    };
    client.onclose = ({ code, reason }) => {
        if (!link.open) return;
        link.open = false;
        socket.end(closeFrame(code, reason || ""));
    };

    const state = { buffer: Buffer.alloc(0), parts: [] };
    socket.on("data", (chunk) => readFrames(state, chunk, (opcode, payload, fin) => {
        if (link.muted) return;
        if (opcode === 0 || opcode === 1) {
            state.parts.push(payload);
            if (!fin) return;
            const text = Buffer.concat(state.parts.splice(0)).toString();
            record(link.uid, "socket", text);
            client.send(text);
        } else if (opcode === 8) {
            const code = payload.length >= 2 ? payload.readUInt16BE(0) : 1005;
            if (link.open) {
                link.open = false;
                socket.end(closeFrame(code, ""));
            }
            client.close(code);
        } else if (opcode === 9) {
            socket.write(frame(10, payload));
        }
    }));
    const gone = () => {
        if (link.open) {
            link.open = false;
            client.close(1006);
        }
    };
    socket.on("close", gone);
    socket.on("error", gone);
}

// ------------------------------------------------------------------ http

async function body(request) {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    return Buffer.concat(chunks).toString();
}

function send(response, status, value) {
    const text = JSON.stringify(value);
    response.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(text) });
    response.end(text);
}

const bots = new Map();
const loop = new RealLoop();
const random = seededRandom(Number(option("seed", 7)));
const localApi = new LocalApi({ worker, env, namespace });

async function controlRequest(path, input) {
    switch (path) {
        case "/__control/refuse-sockets":
            control.refuseSockets = input.count ?? 1;
            return { ok: true };
        case "/__control/refuse-polls":
            control.refusePolls = input.count ?? 1;
            return { ok: true };
        case "/__control/drop": {
            const link = connections.get(input.uid);
            if (!link?.open) return { ok: false };
            if (input.silent) {
                link.muted = true;
                return { ok: true };
            }
            link.open = false;
            link.socket.destroy();
            link.client.close(1006);
            return { ok: true };
        }
        case "/__control/close": {
            const link = connections.get(input.uid);
            if (!link?.open) return { ok: false };
            link.open = false;
            link.socket.end(closeFrame(input.code, input.reason || ""));
            link.client.close(input.code);
            return { ok: true };
        }
        case "/__control/received":
            return { messages: received.get(input.uid) ?? [] };
        case "/__control/stats":
            return stat(input.uid);
        case "/__control/bot": {
            const bot = new Bot({ name: input.name, api: localApi, loop, oracle, random, accuracy: input.accuracy ?? 0.6, think: input.think ?? [400, 1500] });
            bots.set(input.name, bot);
            await bot.signIn();
            if (input.create) await bot.create(input.create);
            else await bot.join(input.code);
            if (input.ready) loop.after(200, () => bot.send({ t: "ready", film: 0 }));
            return { uid: bot.uid, code: bot.code };
        }
        case "/__control/bot-send": {
            bots.get(input.name)?.send(input.msg);
            await namespace.settle();
            return { ok: true };
        }
        case "/__control/bot-drop": {
            bots.get(input.name)?.dropFor(input.ms ?? 5000);
            return { ok: true };
        }
        case "/__control/bot-state": {
            const bot = bots.get(input.name);
            return { finished: bot?.finished ?? null, closedWith: bot?.closedWith ?? null, errors: bot?.errors ?? [] };
        }
        default:
            return null;
    }
}

const server = createServer(async (request, response) => {
    try {
        const url = new URL(request.url, "http://localhost");
        const text = await body(request);
        if (url.pathname.startsWith("/__control/")) {
            const result = await controlRequest(url.pathname, text ? JSON.parse(text) : {});
            return result ? send(response, 200, result) : send(response, 404, { error: "not_found" });
        }

        if (url.pathname.endsWith("/poll")) {
            const uid = uidOf(String(request.headers.authorization || "").replace(/^PvP\s+/, ""));
            if (control.refusePolls > 0) {
                control.refusePolls -= 1;
                if (uid) stat(uid).pollsRefused += 1;
                return send(response, 503, { error: "unavailable", message: "refused by the fake server" });
            }
            if (uid) {
                stat(uid).polls += 1;
                record(uid, "poll", text);
            }
        }

        const headers = {};
        for (const [key, value] of Object.entries(request.headers)) if (typeof value === "string") headers[key] = value;
        const reply = await worker.fetch(
            new Request(`http://${request.headers.host}${url.pathname}${url.search}`, { method: request.method, headers, body: ["GET", "HEAD"].includes(request.method) ? undefined : text }),
            env,
            { waitUntil() {} }
        );
        await namespace.settle();
        const out = Buffer.from(await reply.arrayBuffer());
        const replyHeaders = { "Content-Length": out.length };
        reply.headers.forEach((value, key) => {
            if (key !== "content-length") replyHeaders[key] = value;
        });
        response.writeHead(reply.status, replyHeaders);
        response.end(out);
    } catch (error) {
        console.error(error);
        send(response, 500, { error: "fake_server", message: String(error) });
    }
});

server.on("upgrade", (request, socket) => {
    upgrade(request, socket).catch((error) => {
        console.error(error);
        socket.destroy();
    });
});

server.listen(Number(option("port", 0)), "127.0.0.1", () => {
    console.log(JSON.stringify({ port: server.address().port }));
});
