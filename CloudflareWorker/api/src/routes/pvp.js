// PvP: the profile players show in rooms, and the doors into a room. The
// match itself runs in the room's Durable Object (src/pvp/room.js); these
// routes only create rooms, hand out tickets and pass sockets through.

import { APIError, badRequest, json, readJSON, requireEnum } from "../lib/http.js";
import { authenticate } from "../lib/auth.js";
import { limitByUser } from "../lib/limits.js";
import { readConfig } from "../lib/config.js";
import { MEDIA_TYPES } from "../lib/media.js";
import { loadPvpProfile, updatePvpProfile } from "../lib/pvpNames.js";
import { mintTicket, pvpToken, readPvpToken } from "../lib/pvpTicket.js";
import { FILM_CHOICES, FRAME_CHOICES, TIME_CHOICES, buildSettings, isRoomCode, randomRoomCode } from "../pvp/core.js";

const CREATE_ATTEMPTS = 5;

// Room codes are the only thing keeping strangers out, so they are drawn from
// the CSPRNG rather than Math.random.
function secureRandom() {
    return crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296;
}

function choice(body, field, allowed, fallback) {
    const value = body[field] ?? fallback;
    if (body[field] !== undefined && !allowed.includes(value)) throw badRequest(`${field} must be one of: ${allowed.join(", ")}`);
    return value;
}

function roomStub(env, code) {
    if (!env.PVP_ROOM) throw new APIError(503, "pvp_unavailable", "PvP is not set up on this server");
    return env.PVP_ROOM.get(env.PVP_ROOM.idFromName(code));
}

async function requireEnabled(env) {
    const config = await readConfig(env);
    if (!config.pvpEnabled) throw new APIError(503, "pvp_disabled", "PvP is switched off");
    return config;
}

async function refusal(response) {
    const body = await response.json().catch(() => ({}));
    return new APIError(response.status, body.error || "room_error", body.message || "The room refused");
}

function socketURL(url, code) {
    return `${url.origin.replace(/^http/, "ws")}/v1/pvp/rooms/${code}/ws`;
}

export async function handlePvp(request, env, segments, url) {
    // GET /v1/pvp/profile
    if (segments[0] === "profile" && segments.length === 1 && request.method === "GET") {
        const user = await authenticate(request, env);
        return json(await loadPvpProfile(env, user.uid));
    }

    // PATCH /v1/pvp/profile — {name?, icon?, color?, reroll?}; name null goes
    // back to the generated one
    if (segments[0] === "profile" && segments.length === 1 && request.method === "PATCH") {
        const user = await authenticate(request, env);
        await limitByUser(env, user.uid, "WRITE_LIMITER");
        return json(await updatePvpProfile(env, user.uid, await readJSON(request)));
    }

    if (segments[0] !== "rooms") return null;

    // POST /v1/pvp/rooms — {kind, mediaType, films?, frames?, timeLimitSec?}
    if (segments.length === 1 && request.method === "POST") {
        const user = await authenticate(request, env);
        const config = await requireEnabled(env);
        const body = await readJSON(request);

        const kind = requireEnum(body, "kind", ["room", "duel"]);
        const mediaType = requireEnum(body, "mediaType", MEDIA_TYPES);
        const allowed = String(config.pvpMediaTypes).split(",").map((value) => value.trim());
        if (!allowed.includes(mediaType)) throw new APIError(400, "media_type_disabled", `PvP plays only: ${allowed.join(", ")}`);

        const settings = buildSettings(config, {
            kind,
            mediaType,
            films: choice(body, "films", FILM_CHOICES, config.pvpRoomFilms),
            frames: choice(body, "frames", FRAME_CHOICES, config.pvpFrames),
            timeLimitSec: choice(body, "timeLimitSec", TIME_CHOICES, config.pvpTimeLimitSec)
        });

        await limitByUser(env, user.uid, "WRITE_LIMITER");
        const profile = await loadPvpProfile(env, user.uid);

        for (let attempt = 0; attempt < CREATE_ATTEMPTS; attempt += 1) {
            const code = randomRoomCode(env.PVP_RANDOM ?? secureRandom);
            const response = await roomStub(env, code).fetch("https://room/create", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ code, settings, uid: user.uid })
            });
            if (response.status === 409) continue;
            if (!response.ok) throw await refusal(response);

            const ticket = await mintTicket(env, { ...profile, code }, { now: env.PVP_NOW?.() });
            return json({ code, ticket, socketURL: socketURL(url, code) }, 201);
        }
        throw new APIError(503, "no_free_code", "Could not find a free room code, try again");
    }

    const code = segments[1];
    if (!isRoomCode(code)) throw new APIError(404, "room_not_found", "No room with that code");

    // POST /v1/pvp/rooms/{code}/ticket — join, or come back after a long absence
    if (segments[2] === "ticket" && segments.length === 3 && request.method === "POST") {
        const user = await authenticate(request, env);
        await requireEnabled(env);
        const response = await roomStub(env, code).fetch("https://room/check", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ uid: user.uid })
        });
        if (!response.ok) throw await refusal(response);

        const profile = await loadPvpProfile(env, user.uid);
        return json({ ticket: await mintTicket(env, { ...profile, code }, { now: env.PVP_NOW?.() }), socketURL: socketURL(url, code) });
    }

    // GET /v1/pvp/rooms/{code}/ws and POST …/poll — Authorization: PvP <ticket
    // or resume token>, checked by the room itself
    if ((segments[2] === "ws" && request.method === "GET") || (segments[2] === "poll" && request.method === "POST")) {
        if (segments.length !== 3) return null;
        // Both kinds of token are signed, so a made-up one is refused here
        // without waking the room, and the limit is per player: a fresh fake
        // token cannot buy a fresh allowance. Not by IP: friends behind one VPN
        // exit would share it.
        const claim = await readPvpToken(env, pvpToken(request), code, { now: env.PVP_NOW?.() });
        if (!claim) throw new APIError(401, "token_invalid", "Missing or invalid room token");
        await limitByUser(env, `pvp:${code}:${claim.uid}`, "REQUEST_LIMITER");
        return roomStub(env, code).fetch(request);
    }

    return null;
}
