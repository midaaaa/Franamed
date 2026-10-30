// Who a player is in a PvP room: a nickname, an icon and a colour.
//
// Nicknames are Latin letters, digits and underscores only. A filter cannot keep
// up with look-alike letters across alphabets, invisible characters or emoji,
// and the names end up on little plaques in the 3D hall. Everyone starts with a
// generated name, so nobody is "Player 4821"; a custom one is optional.

import { APIError, badRequest } from "./http.js";
import { seededRandom } from "./frames.js";
import { hashString } from "./daily.js";

export const NAME_MAX_LENGTH = 16;
const NAME_PATTERN = /^[A-Za-z0-9_]{3,16}$/;

// Film jargon and a few single-word nods, nothing trademarked. Every pair is
// tried against the length limit, so the lists can grow freely.
const ADJECTIVES = [
    "Silent", "Noir", "Midnight", "Golden", "Velvet", "Neon", "Grainy", "Wide",
    "Slow", "Late", "Final", "Lost", "Hidden", "Restless", "Rogue", "Lucky",
    "Quiet", "Crimson", "Silver", "Electric", "Lonely", "Brave", "Sleepy", "Wild",
    "Cosmic", "Rainy", "Foggy", "Tiny", "Epic", "Vintage", "Analog", "Retro",
    "Double", "Secret", "Mellow", "Daring", "Stormy", "Dusty", "Pale", "Cult"
];
const NOUNS = [
    "Gaffer", "Grip", "Foley", "Reel", "Dolly", "Boom", "JumpCut", "Cutaway",
    "Matinee", "Usher", "Critic", "Stuntman", "Extra", "Cameo", "Montage", "Closeup",
    "Fadeout", "Spotlight", "Projector", "Ticket", "Popcorn", "Director", "Editor", "Rosebud",
    "Overlook", "Nostromo", "Maltese", "Sequel", "Prequel", "Remake", "Trailer", "Premiere",
    "Encore", "Marquee", "Frame", "Lens", "Tripod", "Slate", "Clapper", "Takes"
];

// Placeholders until the art is picked: the client maps slugs to symbols.
export const ICONS = [
    "popcorn", "clapper", "camera", "film", "ticket", "glasses3d",
    "seat", "spotlight", "masks", "megaphone", "star", "projector"
];
export const COLORS = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink"];

export function generateName(seed) {
    const random = seededRandom(seed);
    for (let attempt = 0; attempt < 20; attempt += 1) {
        const name = ADJECTIVES[Math.floor(random() * ADJECTIVES.length)] + NOUNS[Math.floor(random() * NOUNS.length)];
        if (name.length <= NAME_MAX_LENGTH) return name;
    }
    return NOUNS[seed % NOUNS.length];
}

// Roots, matched as substrings after folding look-alike digits. English plus
// Russian spelled in Latin, since that is what a Latin-only name can carry.
// Kept to roots that do not sit inside ordinary words ("Hitchcock", "class").
const BLOCKED = [
    "fuck", "fuk", "shit", "cunt", "nigg", "nigr", "fagg", "faggot", "bitch", "whore", "slut",
    "rapist", "nazi", "hitler", "porn", "penis", "vagin", "pussy", "dildo", "wank", "jizz",
    "hui", "huy", "xuy", "xui", "pizd", "pisd", "eban", "ebal", "yeba", "ebat", "blya", "blja",
    "suka", "mudak", "pidor", "pidar", "pidr", "gandon", "gondon", "zalup", "shlyuh", "shluh", "dermo"
];
const LOOKALIKES = { 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", 9: "g" };

export function isCleanName(name) {
    const folded = name.toLowerCase().replace(/[0-9]/g, (digit) => LOOKALIKES[digit] ?? "").replace(/_/g, "");
    return !BLOCKED.some((root) => folded.includes(root));
}

export function validateName(value) {
    if (typeof value !== "string" || !NAME_PATTERN.test(value)) {
        throw badRequest("name must be 3–16 Latin letters, digits or underscores");
    }
    if (!isCleanName(value)) throw new APIError(400, "name_rejected", "That name is not allowed");
    return value;
}

// The profile as everyone sees it. With no row the whole thing is derived from
// the uid, so a player who never customises costs no write.
export function pvpProfile(uid, row = null) {
    const hash = hashString(uid);
    return {
        uid,
        name: row?.name ?? generateName(hashString(`${uid}:${row?.name_seed ?? 0}`)),
        customName: Boolean(row?.name),
        // What a hidden name turns into: stable, and never the name itself.
        alias: generateName(hashString(`${uid}:alias`)),
        icon: ICONS.includes(row?.icon) ? row.icon : ICONS[hash % ICONS.length],
        color: COLORS.includes(row?.color) ? row.color : COLORS[(hash >>> 8) % COLORS.length]
    };
}

export async function loadPvpProfile(env, uid) {
    const row = await env.DB.prepare("SELECT * FROM pvp_profiles WHERE uid = ?").bind(uid).first();
    return pvpProfile(uid, row);
}

export async function updatePvpProfile(env, uid, body) {
    const current = await env.DB.prepare("SELECT * FROM pvp_profiles WHERE uid = ?").bind(uid).first();
    let name = current?.name ?? null;
    let seed = current?.name_seed ?? 0;
    let icon = current?.icon ?? null;
    let color = current?.color ?? null;

    if (body.reroll === true) {
        name = null;
        seed += 1;
    } else if (body.name === null) {
        name = null;
    } else if (body.name !== undefined) {
        name = validateName(body.name);
    }
    if (body.icon !== undefined) {
        if (!ICONS.includes(body.icon)) throw badRequest(`icon must be one of: ${ICONS.join(", ")}`);
        icon = body.icon;
    }
    if (body.color !== undefined) {
        if (!COLORS.includes(body.color)) throw badRequest(`color must be one of: ${COLORS.join(", ")}`);
        color = body.color;
    }

    const row = await env.DB.prepare(
        `INSERT INTO pvp_profiles (uid, name, name_seed, icon, color, updated_at) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT (uid) DO UPDATE SET name = excluded.name, name_seed = excluded.name_seed,
                                         icon = excluded.icon, color = excluded.color, updated_at = excluded.updated_at
         RETURNING *`
    ).bind(uid, name, seed, icon, color, Date.now()).first();

    return pvpProfile(uid, row);
}

// Two players with one name in a room: the later one gets "_2", cut short so
// the whole stays within the limit.
export function dedupeName(name, taken) {
    const lower = new Set([...taken].map((value) => value.toLowerCase()));
    if (!lower.has(name.toLowerCase())) return name;
    for (let n = 2; ; n += 1) {
        const suffix = `_${n}`;
        const candidate = name.slice(0, NAME_MAX_LENGTH - suffix.length) + suffix;
        if (!lower.has(candidate.toLowerCase())) return candidate;
    }
}
