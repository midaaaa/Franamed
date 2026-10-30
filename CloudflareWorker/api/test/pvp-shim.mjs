// Stand-ins for what the room object gets from Cloudflare — the namespace, the
// object state with its storage and alarm, the Hibernation WebSocket API — so
// the real src/pvp/room.js runs in node under a clock the test moves by hand.
//
// What is modelled: one event at a time per object (Cloudflare's input gate),
// storage that survives an object being thrown away (hibernation), the runtime
// answering pings without waking the object, and a socket that dies silently.

import { PvpRoom } from "../src/pvp/room.js";

// Node's Response refuses status 101.
PvpRoom.upgradeResponse = (socket) => ({ status: 101, ok: true, webSocket: socket, headers: new Headers() });

export class Clock {
    constructor(time = Date.UTC(2026, 9, 30, 12)) {
        this.time = time;
    }
    now = () => this.time;
}

globalThis.WebSocketRequestResponsePair ??= class {
    constructor(request, response) {
        this.request = request;
        this.response = response;
    }
};

// ------------------------------------------------------------------ sockets

class ServerEnd {
    readyState = 1;
    attachment = null;
    pingAt = null;
    object = null;
    peer = null;

    send(text) {
        if (this.readyState !== 1) throw new Error("socket closed");
        this.peer.receive(text);
    }

    close(code = 1000, reason = "") {
        if (this.readyState === 3) return;
        this.readyState = 3;
        this.peer.closedByServer(code, reason);
    }

    serializeAttachment(value) {
        this.attachment = structuredClone(value);
    }

    deserializeAttachment() {
        return this.attachment === null ? null : structuredClone(this.attachment);
    }
}

export class ClientEnd {
    readyState = 1;
    peer = null;
    onclose = null;
    silent = false;
    #handler = null;
    #held = [];

    // What arrives before anyone listens is held, as a real socket's buffer
    // would: the welcome goes out while the upgrade is still being answered.
    set onmessage(handler) {
        this.#handler = handler;
        for (const text of this.#held.splice(0)) handler(text);
    }

    receive(text) {
        if (this.silent || this.readyState !== 1) return;
        if (this.#handler) this.#handler(text);
        else this.#held.push(text);
    }

    closedByServer(code, reason) {
        if (this.readyState === 3) return;
        this.readyState = 3;
        this.onclose?.({ code, reason });
    }

    send(text) {
        if (this.readyState !== 1 || this.silent) return;
        const server = this.peer;
        const object = server.object;
        if (!object) return;
        if (text === object.ctx.autoResponse?.request) {
            // Answered by the runtime: the object does not wake.
            server.pingAt = object.clock.now();
            this.receive(object.ctx.autoResponse.response);
            return;
        }
        object.messages += 1;
        object.enqueue(() => object.instance.webSocketMessage(server, text));
    }

    close(code = 1000, reason = "") {
        if (this.readyState === 3) return;
        this.readyState = 3;
        const server = this.peer;
        server.readyState = 3;
        server.object?.enqueue(() => server.object.instance.webSocketClose(server, code, reason, true));
    }

    // The network vanished: nothing gets through either way and no close ever
    // arrives — what DPI does to a long-lived socket.
    vanish() {
        this.silent = true;
    }
}

globalThis.WebSocketPair = class {
    constructor() {
        const client = new ClientEnd();
        const server = new ServerEnd();
        client.peer = server;
        server.peer = client;
        this[0] = client;
        this[1] = server;
    }
};

// ------------------------------------------------------------------ object

class Storage {
    values = new Map();
    alarm = null;
    writes = 0;

    async get(key) {
        return this.values.has(key) ? structuredClone(this.values.get(key)) : undefined;
    }
    async put(key, value) {
        this.writes += 1;
        this.values.set(key, structuredClone(value));
    }
    async deleteAll() {
        this.writes += this.values.size;
        this.values.clear();
    }
    async getAlarm() {
        return this.alarm;
    }
    async setAlarm(time) {
        this.writes += 1;
        this.alarm = time;
    }
    async deleteAlarm() {
        this.alarm = null;
    }
}

class ObjectState {
    sockets = [];
    autoResponse = null;

    constructor(object, storage) {
        this.object = object;
        this.storage = storage;
    }

    acceptWebSocket(socket, tags = []) {
        socket.object = this.object;
        socket.tags = tags;
        this.sockets.push(socket);
    }

    getWebSockets(tag) {
        return this.sockets.filter((socket) => socket.readyState === 1 && (tag === undefined || socket.tags.includes(tag)));
    }

    setWebSocketAutoResponse(pair) {
        this.autoResponse = pair;
    }

    getWebSocketAutoResponseTimestamp(socket) {
        return socket.pingAt === null ? null : new Date(socket.pingAt);
    }
}

class FakeObject {
    queue = Promise.resolve();
    requests = 0;
    messages = 0;
    alarms = 0;

    constructor(env, clock) {
        this.env = env;
        this.clock = clock;
        this.storage = new Storage();
        this.ctx = new ObjectState(this, this.storage);
        this.instance = new PvpRoom(this.ctx, env);
    }

    enqueue(work) {
        const run = this.queue.then(work);
        this.queue = run.catch((error) => {
            console.error("object threw", error);
        });
        return run;
    }

    // The object is evicted: memory is gone, storage and sockets stay.
    hibernate() {
        this.instance = new PvpRoom(this.ctx, this.env);
    }
}

export class Namespace {
    objects = new Map();

    constructor(clock) {
        this.clock = clock;
    }

    // Set after construction: the objects need the same env as the worker.
    bind(env) {
        this.env = { ...env, PVP_NOW: this.clock.now };
    }

    idFromName(name) {
        return name;
    }

    object(id) {
        if (!this.objects.has(id)) this.objects.set(id, new FakeObject(this.env, this.clock));
        return this.objects.get(id);
    }

    get(id) {
        return {
            fetch: (input, init) => {
                const request = input instanceof Request ? input : new Request(input, init);
                const object = this.object(id);
                object.requests += 1;
                return object.enqueue(() => object.instance.fetch(request));
            }
        };
    }

    nextAlarm() {
        const times = [...this.objects.values()].map((object) => object.storage.alarm).filter((time) => time !== null);
        return times.length ? Math.min(...times) : null;
    }

    async fireAlarms() {
        for (const object of this.objects.values()) {
            if (object.storage.alarm !== null && object.storage.alarm <= this.clock.now()) {
                object.storage.alarm = null;
                object.alarms += 1;
                object.enqueue(() => object.instance.alarm());
            }
        }
        await this.settle();
    }

    async settle() {
        for (let round = 0; round < 20; round += 1) {
            const queues = [...this.objects.values()].map((object) => object.queue);
            await Promise.all(queues);
            await new Promise((resolve) => setImmediate(resolve));
            if ([...this.objects.values()].every((object, i) => object.queue === queues[i])) return;
        }
    }
}
