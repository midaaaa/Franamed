// One-time tickets that let a socket into a PvP room.
//
// A socket cannot easily carry the access token's refresh dance, and the room
// object should not read D1 to check who is knocking. So an ordinary
// authenticated request mints a ticket that is good for one minute and one
// room, with the player's profile inside it.
//
// Deliberately not a JWT: the MAC covers "pvp-ticket." plus the payload, so
// neither kind of token can be passed off as the other with the shared secret.

import { base64UrlDecode, base64UrlEncode, hmacBase64Url, timingSafeEqual } from "./crypto.js";

export const TICKET_TTL_MS = 60 * 1000;
const PREFIX = "pvp1";

const RESUME_PREFIX = "pvpr1";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

// `prefix.body.mac`, the MAC over a label of its own per kind of token.
async function sign(env, prefix, label, payload) {
    const body = base64UrlEncode(encoder.encode(JSON.stringify(payload)));
    return `${prefix}.${body}.${await hmacBase64Url(env.JWT_SECRET, `${label}.${body}`)}`;
}

// The payload and the MAC, or null for a wrong kind, a bad MAC or a bad body.
async function verify(env, token, prefix, label) {
    const parts = String(token || "").split(".");
    if (parts.length !== 3 || parts[0] !== prefix) return null;
    const expected = await hmacBase64Url(env.JWT_SECRET, `${label}.${parts[1]}`);
    if (!timingSafeEqual(expected, parts[2])) return null;
    try {
        return { payload: JSON.parse(decoder.decode(base64UrlDecode(parts[1]))), mac: parts[2] };
    } catch {
        return null;
    }
}

export async function mintTicket(env, { uid, code, name, alias, icon, color }, { now = Date.now() } = {}) {
    return sign(env, PREFIX, "pvp-ticket", { uid, code, name, alias, icon, color, exp: now + TICKET_TTL_MS });
}

export function isTicket(token) {
    return typeof token === "string" && token.startsWith(`${PREFIX}.`);
}

// The payload plus its MAC, which the room keeps until expiry to refuse a
// second use. Null for anything forged, expired or meant for another room.
export async function readTicket(env, token, code, { now = Date.now() } = {}) {
    const signed = await verify(env, token, PREFIX, "pvp-ticket");
    if (!signed) return null;
    const { payload, mac } = signed;
    if (typeof payload.exp !== "number" || payload.exp < now || payload.code !== code) return null;
    return { ...payload, mac };
}

// The token a player reconnects with for as long as the room lives. Signed like
// a ticket so the worker can turn a made-up one away without waking the room;
// the room still checks it is the one it handed out, which is how a kick or a
// flood ban takes it back.
export async function mintResumeToken(env, { code, uid }) {
    return sign(env, RESUME_PREFIX, "pvp-resume", { code, uid, n: base64UrlEncode(crypto.getRandomValues(new Uint8Array(12))) });
}

export async function readResumeToken(env, token, code) {
    const signed = await verify(env, token, RESUME_PREFIX, "pvp-resume");
    return signed?.payload.code === code ? signed.payload : null;
}

// Who a ws or poll request claims to be, checked by signature alone. The
// worker uses it to refuse forgeries and to key the rate limit by player.
export async function readPvpToken(env, token, code, { now = Date.now() } = {}) {
    if (isTicket(token)) return readTicket(env, token, code, { now });
    return readResumeToken(env, token, code);
}

// Tokens travel in a header, never the URL: URLs end up in request logs.
export function pvpToken(request) {
    const header = request.headers.get("Authorization") || "";
    return header.startsWith("PvP ") ? header.slice(4).trim() : null;
}
