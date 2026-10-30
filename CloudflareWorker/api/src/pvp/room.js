// The Durable Object behind one room code: sockets, the alarm and storage
// around the rules in core.js.
//
// Built for hibernation, because the free plan bills an object for every
// second it stays awake: sockets are accepted through the Hibernation API,
// pings are answered by the runtime without waking the object, and every timer
// is the object's single alarm — a setTimeout would keep it awake. Whatever
// must survive a nap lives in one stored value, "state".

import { createRoom, joinRefusal, nextAlarm, reduce } from "./core.js";
import { loadMatchFilms } from "./films.js";
import { isTicket, mintResumeToken, pvpToken, readTicket } from "../lib/pvpTicket.js";

const PING = '{"t":"ping"}';
const PONG = '{"t":"pong"}';
// A socket that neither pinged nor spoke for this long is treated as gone even
// if its close never arrived, which is how sockets die behind DPI.
const STALE_SOCKET_MS = 30 * 1000;
// Every incoming message is a billed wake-up shared by the whole account, so
// each socket gets a bucket: 30 at once, one more every 2 s. A player needs a
// handful a film. Pings are answered by the runtime and never reach it.
const BUCKET_SIZE = 30;
const BUCKET_REFILL_MS = 2000;
const MAX_MESSAGE_CHARS = 4096;

function reply(body, status = 200) {
    return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });
}

const ERROR_STATUS = {
    room_not_found: 404,
    room_exists: 409,
    kicked: 403,
    room_full: 409,
    match_running: 409,
    ticket_used: 401,
    ticket_invalid: 401,
    resume_invalid: 401
};

function refuse(code) {
    return reply({ error: code, message: code.replace(/_/g, " ") }, ERROR_STATUS[code] ?? 400);
}

export class PvpRoom {
    // Swapped out by the tests: Node's Response refuses status 101.
    static upgradeResponse = (socket) => new Response(null, { status: 101, webSocket: socket });

    constructor(ctx, env) {
        this.ctx = ctx;
        this.env = env;
        this.state = undefined;
        if (typeof WebSocketRequestResponsePair !== "undefined") {
            ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(PING, PONG));
        }
    }

    now() {
        return this.env.PVP_NOW ? this.env.PVP_NOW() : Date.now();
    }

    async load() {
        if (this.state === undefined) this.state = (await this.ctx.storage.get("state")) ?? null;
        return this.state;
    }

    async fetch(request) {
        const url = new URL(request.url);
        const action = url.pathname.split("/").filter(Boolean).pop();
        const state = await this.load();

        if (action === "create" && request.method === "POST") {
            if (state) return refuse("room_exists");
            const body = await request.json();
            this.state = createRoom({ code: body.code, settings: body.settings, createdBy: body.uid, now: this.now() });
            await this.save({ alarmAt: nextAlarm(this.state) });
            return reply({ code: body.code }, 201);
        }

        if (!state || state.phase === "closed") return refuse("room_not_found");

        if (action === "check" && request.method === "POST") {
            const body = await request.json();
            const refusal = joinRefusal(state, body.uid);
            return refusal ? refuse(refusal) : reply({ ok: true, kind: state.settings.kind });
        }

        if (action === "ws" && request.method === "GET") return this.connect(request, url);

        if (action === "poll" && request.method === "POST") {
            let body;
            try {
                body = await request.json();
            } catch {
                return refuse("bad_request");
            }
            const result = await this.dispatch({
                type: "poll",
                token: pvpToken(request),
                lastSeq: Number.isInteger(body.lastSeq) ? body.lastSeq : -1,
                send: body.send
            });
            if (result.reply?.error) return refuse(result.reply.error);
            return reply({ messages: result.reply.messages });
        }

        return refuse("not_found");
    }

    async connect(request, url) {
        if (request.headers.get("Upgrade") !== "websocket") return refuse("bad_request");
        const token = pvpToken(request);
        const lastSeq = Number.parseInt(url.searchParams.get("lastSeq") ?? "", 10);
        let event;

        if (isTicket(token)) {
            const ticket = await readTicket(this.env, token, this.state.code, { now: this.now() });
            if (!ticket) return refuse("ticket_invalid");
            event = { type: "connect", via: "ticket", ticket, resumeToken: await mintResumeToken(this.env, { code: this.state.code, uid: ticket.uid }), lastSeq };
        } else if (token) {
            event = { type: "connect", via: "resume", token, lastSeq };
        } else {
            return refuse("ticket_invalid");
        }

        // The socket is accepted before the event runs, so the welcome and the
        // broadcasts of this very step reach it.
        const pair = new WebSocketPair();
        const [client, server] = Object.values(pair);
        const result = await this.dispatch(event, {
            beforeDeliver: (uid) => {
                for (const old of this.ctx.getWebSockets(uid)) old.close(4001, "replaced");
                this.ctx.acceptWebSocket(server, [uid]);
                server.serializeAttachment({ uid, at: this.now() });
            }
        });

        if (result.reply?.error) return refuse(result.reply.error);
        return PvpRoom.upgradeResponse(client);
    }

    async webSocketMessage(socket, data) {
        // Already closed for flooding: what was still in flight is not counted again.
        if (socket.readyState !== 1) return;
        const attachment = socket.deserializeAttachment() || {};
        if (data === PING) {
            socket.send(PONG);
            return;
        }

        const now = this.now();
        const text = typeof data === "string" ? data : new TextDecoder().decode(data);
        const bucket = attachment.bucket ?? { tokens: BUCKET_SIZE, at: now };
        bucket.tokens = Math.min(BUCKET_SIZE, bucket.tokens + (now - bucket.at) / BUCKET_REFILL_MS);
        bucket.at = now;
        if (text.length > MAX_MESSAGE_CHARS || bucket.tokens < 1) {
            await this.dispatch({ type: "flood", uid: attachment.uid });
            return;
        }
        bucket.tokens -= 1;
        attachment.bucket = bucket;
        attachment.at = now;
        socket.serializeAttachment(attachment);

        let msg;
        try {
            msg = JSON.parse(text);
        } catch {
            return;
        }
        await this.dispatch({ type: "message", uid: attachment.uid, msg });
    }

    async webSocketClose(socket) {
        await this.socketGone(socket);
    }

    async webSocketError(socket) {
        await this.socketGone(socket);
    }

    async socketGone(socket) {
        const uid = socket.deserializeAttachment()?.uid;
        if (!uid) return;
        const others = this.ctx.getWebSockets(uid).filter((other) => other !== socket && other.readyState !== 3);
        if (others.length) return;
        await this.dispatch({ type: "disconnect", uid });
    }

    async alarm() {
        await this.dispatch({ type: "tick" });
    }

    // Sockets that went silent without a close count as gone, from the last
    // sign of life rather than from when it was noticed: a duel's forfeit clock
    // must not get 30 s longer for a socket that died quietly. Checked on every
    // wake-up rather than on a timer of its own.
    staleEvents(now) {
        const events = [];
        const live = new Map();
        const lastSeen = new Map();
        for (const socket of this.ctx.getWebSockets()) {
            const attachment = socket.deserializeAttachment() || {};
            const pinged = this.ctx.getWebSocketAutoResponseTimestamp?.(socket)?.getTime() ?? 0;
            const last = Math.max(attachment.at ?? 0, pinged);
            lastSeen.set(attachment.uid, Math.max(lastSeen.get(attachment.uid) ?? 0, last));
            if (now - last > STALE_SOCKET_MS) {
                try {
                    socket.close(4008, "stale");
                } catch {
                    // Already closing.
                }
                if (!live.has(attachment.uid)) live.set(attachment.uid, false);
            } else {
                live.set(attachment.uid, true);
            }
        }
        for (const [uid, alive] of live) if (uid && !alive) events.push({ type: "disconnect", uid, since: lastSeen.get(uid) });
        return events;
    }

    async dispatch(event, { beforeDeliver } = {}) {
        const state = await this.load();
        if (!state) return { reply: { error: "room_not_found" } };

        const now = this.now();
        const outcomes = [];
        for (const stale of this.staleEvents(now)) outcomes.push(reduce(state, stale, now));
        const main = reduce(state, event, now);
        outcomes.push(main);
        if (main.reply?.uid && beforeDeliver) beforeDeliver(main.reply.uid);

        // Films come from D1 between two steps of the same wake-up.
        for (let i = 0; i < outcomes.length; i += 1) {
            for (const effect of outcomes[i].effects) {
                if (effect.type !== "loadFilms") continue;
                let films = [];
                try {
                    films = await loadMatchFilms(this.env, { ...effect, now });
                } catch (error) {
                    console.error("pvp films failed", error?.stack || error);
                }
                outcomes.push(reduce(state, { type: "filmsLoaded", films }, this.now()));
            }
        }

        for (const outcome of outcomes) this.deliver(outcome);

        if (outcomes.some((outcome) => outcome.effects.some((effect) => effect.type === "destroy"))) {
            await this.destroy();
            return main;
        }

        await this.save({ alarmAt: outcomes[outcomes.length - 1].alarmAt });
        return main;
    }

    deliver({ out, closes }) {
        for (const { to, msg } of out) {
            const text = JSON.stringify(msg);
            const sockets = to === null ? this.ctx.getWebSockets() : this.ctx.getWebSockets(to);
            for (const socket of sockets) {
                try {
                    socket.send(text);
                } catch {
                    // A socket that died mid-send is picked up as stale later.
                }
            }
        }
        for (const { uid, code, reason } of closes) {
            for (const socket of this.ctx.getWebSockets(uid)) {
                try {
                    socket.close(code, reason);
                } catch {
                    // Already closing.
                }
            }
        }
    }

    async save({ alarmAt }) {
        await this.ctx.storage.put("state", this.state);
        // setAlarm is a billed write, so it is only called when the time moves.
        const current = await this.ctx.storage.getAlarm();
        if (alarmAt === null) {
            if (current !== null) await this.ctx.storage.deleteAlarm();
        } else if (current !== alarmAt) {
            await this.ctx.storage.setAlarm(alarmAt);
        }
    }

    async destroy() {
        for (const socket of this.ctx.getWebSockets()) {
            try {
                socket.close(4004, "room_closed");
            } catch {
                // Already closing.
            }
        }
        await this.ctx.storage.deleteAlarm();
        await this.ctx.storage.deleteAll();
        this.state = null;
    }
}
