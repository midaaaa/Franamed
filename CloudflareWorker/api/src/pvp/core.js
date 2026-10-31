// The rules of a PvP match, with no Cloudflare in sight.
//
// Everything here is (state, event, now) → (state, messages, alarm). The room
// object (room.js) turns sockets and alarms into events and carries the result
// out; the tests and the bots drive these functions directly. Time comes in as
// an argument, so a whole match can be played in a test in a few milliseconds.
//
// The state is mutated in place and must stay plain JSON: the room stores it
// after every event and reloads it after hibernating. See docs/pvp.md.

import { dedupeName } from "../lib/pvpNames.js";

// Digits only, so phones show the number pad.
export const ROOM_CODE_ALPHABET = "0123456789";
export const ROOM_CODE_LENGTH = 6;
export const FILM_CHOICES = [5, 10, 15];
export const FRAME_CHOICES = [6, 4, 3];
export const TIME_CHOICES = [30, 45, 60];

// A poll client that has not asked for this long is offline.
export const POLL_STALE_MS = 10 * 1000;
const PLAYED_MEMORY = 60;
// A socket that floods is closed; the third time its player is out of the
// room, or else reconnecting with the resume token would start it over.
export const FLOOD_STRIKES = 3;
const OUTBOX_LIMIT = 50;

const MATCH_PHASES = ["loading", "ready", "reveal", "countdown", "playing"];
const PAUSABLE_PHASES = ["ready", "reveal", "countdown", "playing"];

export function isRoomCode(value) {
    return typeof value === "string" && value.length === ROOM_CODE_LENGTH
        && [...value].every((char) => ROOM_CODE_ALPHABET.includes(char));
}

export function randomRoomCode(random = Math.random) {
    let code = "";
    for (let i = 0; i < ROOM_CODE_LENGTH; i += 1) code += ROOM_CODE_ALPHABET[Math.floor(random() * ROOM_CODE_ALPHABET.length)];
    return code;
}

// ------------------------------------------------------------------ settings

// The admin's numbers and the host's choices, frozen into the room. Choices are
// checked by the caller; this only assembles.
export function buildSettings(config, { kind, mediaType, films, frames, timeLimitSec }) {
    const duel = kind === "duel";
    return {
        kind,
        mediaType,
        films: duel ? config.pvpDuelMaxFilms : films,
        frames,
        timeLimitSec,
        frameBase: String(config.pvpFrameBase).split(",").map(Number),
        timeBonusMax: config.pvpTimeBonusMax,
        afterFirstCorrectSec: config.pvpAfterFirstCorrectSec,
        countdownSec: config.pvpCountdownSec,
        revealSec: config.pvpRevealSec,
        readyTimeoutSec: config.pvpReadyTimeoutSec,
        hp: config.pvpDuelHP,
        multiplierFrom: config.pvpDuelMultiplierFrom,
        multiplierStep: config.pvpDuelMultiplierStep,
        forfeitSec: config.pvpDuelForfeitSec,
        hostGraceSec: config.pvpHostGraceSec,
        pauseMaxSec: config.pvpPauseMaxSec,
        maxPlayers: duel ? 2 : config.pvpRoomMaxPlayers,
        idleCleanupSec: config.pvpIdleCleanupSec
    };
}

function publicSettings(settings) {
    const base = {
        kind: settings.kind,
        mediaType: settings.mediaType,
        films: settings.films,
        frames: settings.frames,
        timeLimitSec: settings.timeLimitSec,
        maxPlayers: settings.maxPlayers
    };
    return settings.kind === "duel" ? { ...base, hp: settings.hp, maxFilms: settings.films } : base;
}

// ------------------------------------------------------------------ scoring

// Frame first, time second: the bonus stays under the gap between frames, so
// clicking through to an easier frame never beats knowing the film earlier.
export function filmPoints(settings, frame, ms) {
    const base = settings.frameBase[frame - 1] ?? 0;
    const limit = settings.timeLimitSec * 1000;
    return base + Math.round(settings.timeBonusMax * Math.max(0, 1 - ms / limit));
}

// Raises what a film is worth for both, so a duel of misses still ends.
export function duelMultiplier(settings, filmNumber) {
    if (filmNumber < settings.multiplierFrom) return 1;
    return 1 + settings.multiplierStep * (filmNumber - settings.multiplierFrom + 1);
}

// ------------------------------------------------------------------ room

export function createRoom({ code, settings, createdBy, now }) {
    return {
        v: 1,
        code,
        settings,
        createdBy,
        createdAt: now,
        seq: 0,
        phase: "lobby",
        hostUid: null,
        hostAbsentSince: null,
        players: {},
        kicked: [],
        usedTickets: {},
        played: {},
        matchNo: 0,
        match: null,
        pause: null,
        finished: null,
        finishedAt: null,
        newMatchVotes: [],
        emptySince: now
    };
}

// Why this uid may not take a seat, or null. Read by the ticket route before it
// mints anything, and again on connect.
export function joinRefusal(state, uid) {
    if (!state || state.phase === "closed") return "room_not_found";
    if (state.kicked.includes(uid)) return "kicked";
    if (state.players[uid]) return null;
    if (state.settings.kind === "duel" && state.phase !== "lobby") return "match_running";
    const seated = Object.values(state.players).filter((player) => !player.left).length;
    if (seated >= state.settings.maxPlayers) return "room_full";
    return null;
}

// ------------------------------------------------------------------ reduce

// Events:
//   {type: "connect", via: "ticket", ticket, resumeToken, lastSeq}  — ticket already verified
//   {type: "connect", via: "resume", token, lastSeq}
//   {type: "disconnect", uid, since?}  — since: last sign of life, for silent sockets
//   {type: "message", uid, msg}
//   {type: "poll", token, lastSeq, send: [msg]}
//   {type: "tick"}
//   {type: "flood", uid}                    — the room object caught a socket flooding
//   {type: "filmsLoaded", films}  — empty when loading failed
//
// Returns {out: [{to, msg}], closes: [{uid, code, reason}], effects, reply,
// alarmAt}. `to` null means everyone on a socket.
export function reduce(state, event, now) {
    const ctx = { state, now, out: [], closes: [], effects: [], reply: null, bumped: false };

    advance(ctx);
    if (state.phase !== "closed") {
        switch (event.type) {
            case "connect": connect(ctx, event); break;
            case "disconnect": disconnect(ctx, event.uid, event.since); break;
            case "message": message(ctx, event.uid, event.msg); break;
            case "poll": poll(ctx, event); break;
            case "flood": flood(ctx, event.uid); break;
            case "filmsLoaded": filmsLoaded(ctx, event.films); break;
            default: break;
        }
        advance(ctx);
    }

    return { out: ctx.out, closes: ctx.closes, effects: ctx.effects, reply: ctx.reply, alarmAt: nextAlarm(state) };
}

// ------------------------------------------------------------------ output

// One seq per event, however many messages it sends.
function bump(ctx) {
    if (ctx.bumped) return;
    ctx.state.seq += 1;
    ctx.bumped = true;
}

function broadcast(ctx, msg) {
    bump(ctx);
    ctx.out.push({ to: null, msg: { ...msg, seq: ctx.state.seq } });
}

// A poll client has no socket: what is meant for it alone waits in its outbox,
// and everything broadcast reaches it as the next snapshot.
function tell(ctx, uid, msg) {
    const player = ctx.state.players[uid];
    const stamped = { ...msg, seq: ctx.state.seq };
    if (player?.transport === "poll") {
        player.outbox.push(stamped);
        if (player.outbox.length > OUTBOX_LIMIT) player.outbox.shift();
    } else {
        ctx.out.push({ to: uid, msg: stamped });
    }
}

function fail(ctx, uid, code, message) {
    tell(ctx, uid, { t: "error", code, message });
}

function snapshotAll(ctx) {
    // The phase moved in a way no single message describes; everyone redraws.
    bump(ctx);
    for (const uid of Object.keys(ctx.state.players)) tell(ctx, uid, snapshot(ctx.state, uid, ctx.now));
}

// ------------------------------------------------------------------ players

function publicPlayer(state, player, now) {
    const result = {
        uid: player.uid,
        name: player.nameHidden ? player.alias : player.name,
        alias: player.alias,
        icon: player.icon,
        color: player.color,
        isHost: state.hostUid === player.uid,
        ready: player.ready,
        connection: player.connection,
        left: player.left,
        joinedAt: player.joinedAt
    };
    if (state.settings.kind === "duel") {
        const deadline = forfeitAt(state, player);
        if (deadline !== null) result.forfeitInMs = Math.max(0, deadline - now);
    }
    return result;
}

function announce(ctx, uid) {
    const player = ctx.state.players[uid];
    if (player) broadcast(ctx, { t: "player", player: publicPlayer(ctx.state, player, ctx.now) });
}

function seated(state) {
    return Object.values(state.players).filter((player) => !player.left);
}

function present(state) {
    return seated(state).filter((player) => player.connection !== "offline");
}

function byJoin(a, b) {
    return a.joinedAt - b.joinedAt || (a.uid < b.uid ? -1 : 1);
}

function uniqueName(state, uid, name) {
    return dedupeName(name, Object.values(state.players).filter((player) => player.uid !== uid).map((player) => player.name));
}

function uidByToken(state, token) {
    return Object.keys(state.players).find((key) => state.players[key].resumeToken === token);
}

// Back on a socket or a poll: no longer absent, and the room is not empty.
function cameBack(ctx, uid) {
    const { state } = ctx;
    const player = state.players[uid];
    player.left = false;
    player.connection = "online";
    player.absentSince = null;
    if (state.hostUid === uid) state.hostAbsentSince = null;
    state.emptySince = null;
    announce(ctx, uid);
}

// ------------------------------------------------------------------ connect

function connect(ctx, event) {
    const { state, now } = ctx;
    const seqBefore = state.seq;
    let uid;

    if (event.via === "ticket") {
        const ticket = event.ticket;
        for (const [mac, exp] of Object.entries(state.usedTickets)) if (exp < now) delete state.usedTickets[mac];
        if (state.usedTickets[ticket.mac]) {
            ctx.reply = { error: "ticket_used" };
            return;
        }
        const refusal = joinRefusal(state, ticket.uid);
        if (refusal) {
            ctx.reply = { error: refusal };
            return;
        }
        state.usedTickets[ticket.mac] = ticket.exp;
        uid = ticket.uid;

        const existing = state.players[uid];
        if (existing) {
            Object.assign(existing, { icon: ticket.icon, color: ticket.color, alias: ticket.alias });
            existing.name = uniqueName(state, uid, ticket.name);
        } else {
            state.players[uid] = {
                uid,
                name: uniqueName(state, uid, ticket.name),
                alias: ticket.alias,
                icon: ticket.icon,
                color: ticket.color,
                joinedAt: now,
                ready: false,
                connection: "offline",
                left: false,
                absentSince: null,
                nameHidden: false,
                resumeToken: event.resumeToken,
                transport: "ws",
                lastPollAt: null,
                outbox: [],
                total: 0,
                hp: state.settings.hp
            };
        }
        if (!state.hostUid && state.settings.kind === "room") state.hostUid = uid;
    } else {
        uid = uidByToken(state, event.token);
        if (!uid) {
            ctx.reply = { error: "resume_invalid" };
            return;
        }
    }

    const player = state.players[uid];
    player.transport = "ws";
    cameBack(ctx, uid);
    // First on the wire: anything broadcast in this same step is already in
    // the snapshot, and the client drops what is not newer than it.
    const welcome = { t: "welcome", seq: state.seq, you: { uid, resumeToken: player.resumeToken } };
    // The client missed nothing if it saw everything before this connect.
    if (event.via === "ticket" || event.lastSeq !== seqBefore) welcome.snapshot = snapshot(state, uid, now);
    ctx.out.unshift({ to: uid, msg: welcome });
    ctx.reply = { uid };
}

function goneQuiet(ctx, uid, since) {
    const { state } = ctx;
    const player = state.players[uid];
    if (!player || player.connection === "offline") return;
    player.connection = "offline";
    player.absentSince ??= since;
    if (state.hostUid === uid) state.hostAbsentSince = since;
    if (!Object.values(state.players).some((p) => p.connection !== "offline")) state.emptySince = since;
    announce(ctx, uid);
}

function disconnect(ctx, uid, since) {
    const player = ctx.state.players[uid];
    if (!player || player.transport !== "ws") return;
    goneQuiet(ctx, uid, Math.min(ctx.now, since ?? ctx.now));
}

function poll(ctx, event) {
    const { state, now } = ctx;
    const uid = uidByToken(state, event.token);
    if (!uid) {
        ctx.reply = { error: "resume_invalid" };
        return;
    }
    const player = state.players[uid];
    player.transport = "poll";
    player.lastPollAt = now;
    if (player.connection === "offline" || player.left) cameBack(ctx, uid);

    for (const msg of Array.isArray(event.send) ? event.send.slice(0, 20) : []) message(ctx, uid, msg);
    advance(ctx);

    const messages = player.outbox.splice(0);
    if (event.lastSeq !== state.seq) messages.push({ ...snapshot(state, uid, now), seq: state.seq });
    ctx.reply = { uid, messages };
}

// ------------------------------------------------------------------ messages

function message(ctx, uid, msg) {
    const { state } = ctx;
    const player = state.players[uid];
    if (!player || !msg || typeof msg !== "object" || typeof msg.t !== "string") return;

    const isHost = state.settings.kind === "room" && state.hostUid === uid;
    const hostOnly = () => {
        if (isHost) return true;
        fail(ctx, uid, "not_host", "Only the host can do that");
        return false;
    };

    switch (msg.t) {
        case "ready": return ready(ctx, uid, msg);
        case "unready":
            if (state.phase === "lobby" && player.ready) {
                player.ready = false;
                announce(ctx, uid);
            }
            return;
        case "guess": return answer(ctx, uid, msg, true);
        case "skip": return answer(ctx, uid, msg, false);
        case "frameBroken": return frameBroken(ctx, uid, msg);
        case "away": return away(ctx, uid, msg.away === true);
        case "leave": return leave(ctx, uid);
        case "settings": if (hostOnly()) changeSettings(ctx, uid, msg); return;
        case "start":
            if (!hostOnly()) return;
            if (state.phase !== "lobby") return fail(ctx, uid, "bad_phase", "The match has already started");
            if (seated(state).length < 2) return fail(ctx, uid, "not_enough_players", "At least two players are needed");
            return startMatch(ctx);
        case "pause": if (hostOnly()) pause(ctx, uid); return;
        case "resume":
            if (!hostOnly()) return;
            if (state.pause) resume(ctx);
            return;
        case "kick": if (hostOnly()) kick(ctx, uid, msg.uid); return;
        case "hideName":
            if (!hostOnly()) return;
            if (state.players[msg.uid] && !state.players[msg.uid].nameHidden) {
                state.players[msg.uid].nameHidden = true;
                announce(ctx, msg.uid);
            }
            return;
        case "newMatch": return newMatch(ctx, uid);
        default:
            return fail(ctx, uid, "bad_message", `Unknown message "${msg.t}"`);
    }
}

function ready(ctx, uid, msg) {
    const { state } = ctx;
    const player = state.players[uid];

    if (state.phase === "lobby") {
        if (player.ready) return;
        player.ready = true;
        announce(ctx, uid);
        if (state.settings.kind === "duel") {
            const players = seated(state);
            if (players.length === 2 && players.every((p) => p.ready && p.connection !== "offline")) startMatch(ctx);
        }
        return;
    }

    if ((state.phase === "ready" || state.phase === "reveal") && msg.film === state.match.film.index + 1) {
        if (!state.match.film.readyUids.includes(uid)) state.match.film.readyUids.push(uid);
        if (state.phase === "ready" && !state.pause && everyoneReady(state)) startCountdown(ctx);
    }
}

function everyoneReady(state) {
    return present(state).every((player) => state.match.film.readyUids.includes(player.uid));
}

function away(ctx, uid, isAway) {
    const player = ctx.state.players[uid];
    if (player.connection === "offline") return;
    const next = isAway ? "away" : "online";
    if (player.connection === next) return;
    player.connection = next;
    // A minimised app counts towards a duel forfeit, as in chess.
    player.absentSince = isAway ? (player.absentSince ?? ctx.now) : null;
    announce(ctx, uid);
}

function changeSettings(ctx, uid, msg) {
    const { state } = ctx;
    if (state.phase !== "lobby") return fail(ctx, uid, "bad_phase", "Settings change only in the lobby");
    const next = { ...state.settings };
    if (msg.films !== undefined) {
        if (!FILM_CHOICES.includes(msg.films)) return fail(ctx, uid, "bad_message", `films must be one of ${FILM_CHOICES.join(", ")}`);
        next.films = msg.films;
    }
    if (msg.frames !== undefined) {
        if (!FRAME_CHOICES.includes(msg.frames)) return fail(ctx, uid, "bad_message", `frames must be one of ${FRAME_CHOICES.join(", ")}`);
        next.frames = msg.frames;
    }
    if (msg.timeLimitSec !== undefined) {
        if (!TIME_CHOICES.includes(msg.timeLimitSec)) return fail(ctx, uid, "bad_message", `timeLimitSec must be one of ${TIME_CHOICES.join(", ")}`);
        next.timeLimitSec = msg.timeLimitSec;
    }
    state.settings = next;
    broadcast(ctx, { t: "settings", settings: publicSettings(next) });
}

function leave(ctx, uid) {
    const { state, now } = ctx;
    const player = state.players[uid];
    ctx.closes.push({ uid, code: 4000, reason: "left" });

    if (state.phase === "lobby" || state.phase === "finished") {
        delete state.players[uid];
        broadcast(ctx, { t: "playerRemoved", uid, reason: "left" });
        if (state.hostUid === uid) transferHost(ctx);
    } else if (state.settings.kind === "duel") {
        player.left = true;
        player.connection = "offline";
        return forfeit(ctx, uid);
    } else {
        player.left = true;
        player.connection = "offline";
        player.absentSince ??= now;
        announce(ctx, uid);
        if (state.hostUid === uid) transferHost(ctx);
        if (state.phase === "playing") checkFilmEnd(ctx);
    }
    if (!Object.values(state.players).some((p) => p.connection !== "offline")) state.emptySince = now;
}

function kick(ctx, hostUid, uid) {
    if (!ctx.state.players[uid] || uid === hostUid) return fail(ctx, hostUid, "bad_message", "No such player to remove");
    removePlayer(ctx, uid, "kicked", 4003);
}

function flood(ctx, uid) {
    const { state } = ctx;
    const player = state.players[uid];
    if (!player) return;
    player.floods = (player.floods ?? 0) + 1;
    if (player.floods < FLOOD_STRIKES) {
        ctx.closes.push({ uid, code: 4029, reason: "too_many_messages" });
        return;
    }
    if (state.settings.kind === "duel" && state.phase !== "lobby") {
        if (MATCH_PHASES.includes(state.phase)) forfeit(ctx, uid);
        state.kicked.push(uid);
        ctx.closes.push({ uid, code: 4030, reason: "removed_for_flooding" });
        player.resumeToken = null;
        player.left = true;
        player.connection = "offline";
        announce(ctx, uid);
        return;
    }
    removePlayer(ctx, uid, "flood", 4030);
}

// Out for good: no seat, no way back in, and their points gone from every
// result. A duel keeps the seat (see flood) so the result still has two sides.
function removePlayer(ctx, uid, reason, code) {
    const { state } = ctx;
    delete state.players[uid];
    state.kicked.push(uid);
    ctx.closes.push({ uid, code, reason });

    // Their points go with them, from the running film and from every result.
    if (state.match) {
        delete state.match.film.participants[uid];
        for (const film of state.match.results) film.results = film.results.filter((result) => result.uid !== uid);
        if (state.match.lastReveal) {
            state.match.lastReveal.results = state.match.lastReveal.results.filter((result) => result.uid !== uid);
            state.match.lastReveal.standings = standings(state);
        }
    }
    broadcast(ctx, { t: "playerRemoved", uid, reason });

    if (state.phase === "finished" && state.finished) {
        state.finished = { ...state.finished, standings: standings(state), films: finishedFilms(state) };
        broadcast(ctx, { t: "finished", ...state.finished });
    }
    if (state.phase === "playing") checkFilmEnd(ctx);
    if (state.phase === "ready" && !state.pause && everyoneReady(state)) startCountdown(ctx);
}

function transferHost(ctx) {
    const { state } = ctx;
    if (state.settings.kind !== "room") return;
    const previous = state.hostUid;
    const next = present(state).filter((player) => player.uid !== previous).sort(byJoin)[0];
    if (!next) return;
    state.hostUid = next.uid;
    state.hostAbsentSince = null;
    if (state.players[previous]) announce(ctx, previous);
    announce(ctx, next.uid);
}

function newMatch(ctx, uid) {
    const { state } = ctx;
    if (state.phase !== "finished") return fail(ctx, uid, "bad_phase", "The match is not over");
    if (state.settings.kind === "room") {
        if (state.hostUid !== uid) return fail(ctx, uid, "not_host", "Only the host can do that");
    } else {
        if (!state.newMatchVotes.includes(uid)) state.newMatchVotes.push(uid);
        if (state.newMatchVotes.length < seated(state).length || seated(state).length < 2) return;
    }

    for (const player of Object.values(state.players)) {
        if (player.left) {
            delete state.players[player.uid];
            continue;
        }
        player.ready = false;
        player.total = 0;
        player.hp = state.settings.hp;
        player.absentSince = player.connection === "online" ? null : player.absentSince;
    }
    state.phase = "lobby";
    state.match = null;
    state.finished = null;
    state.finishedAt = null;
    state.newMatchVotes = [];
    snapshotAll(ctx);
}

// ------------------------------------------------------------------ match

function startMatch(ctx) {
    const { state, now } = ctx;
    state.phase = "loading";
    state.matchNo += 1;
    for (const player of Object.values(state.players)) {
        player.total = 0;
        player.hp = state.settings.hp;
        // Time away in the lobby does not count towards a duel forfeit.
        if (player.absentSince !== null) player.absentSince = now;
    }
    ctx.effects.push({
        type: "loadFilms",
        mediaType: state.settings.mediaType,
        frames: state.settings.frames,
        count: state.settings.films,
        played: { ...state.played },
        seedText: `${state.code}:${state.matchNo}`
    });
    broadcast(ctx, { t: "loading" });
}

function filmsLoaded(ctx, films) {
    const { state, now } = ctx;
    if (state.phase !== "loading") return;

    if (!films.length) {
        state.phase = "lobby";
        for (const player of Object.values(state.players)) player.ready = false;
        snapshotAll(ctx);
        for (const uid of Object.keys(state.players)) fail(ctx, uid, "pool_empty", "No titles to play right now");
        return;
    }

    state.match = { films, results: [], lastReveal: null, revealEndsAt: null, readyDeadline: now + state.settings.readyTimeoutSec * 1000, film: newFilm(0) };
    state.phase = "ready";
    broadcast(ctx, prepareMessage(state));
}

function newFilm(index) {
    return { index, readyUids: [], startedAt: null, deadline: null, blockedUntil: 0, firstCorrectAt: null, participants: {} };
}

function prepareMessage(state) {
    const film = state.match.films[state.match.film.index];
    return { t: "prepare", film: state.match.film.index + 1, total: state.match.films.length, frames: film.frames, spares: film.spares };
}

function startCountdown(ctx) {
    const { state, now } = ctx;
    const film = state.match.film;
    const candidates = seated(state);
    let participants = state.settings.kind === "duel"
        ? candidates
        : candidates.filter((player) => film.readyUids.includes(player.uid));
    if (!participants.length) participants = candidates.filter((player) => player.connection !== "offline");

    for (const player of participants) {
        film.participants[player.uid] = { frame: 1, status: "thinking", solvedAtFrame: null, ms: null, points: 0 };
    }
    film.startedAt = now + state.settings.countdownSec * 1000;
    film.deadline = film.startedAt + state.settings.timeLimitSec * 1000;
    state.phase = "countdown";
    state.match.readyDeadline = null;

    broadcast(ctx, {
        t: "countdown",
        film: film.index + 1,
        startsInMs: film.startedAt - now,
        timeLimitMs: state.settings.timeLimitSec * 1000,
        participants: Object.keys(film.participants)
    });
}

// Typed text counts like the round on the phone: the same title, any letter case.
function namesTitle(text, title) {
    if (typeof text !== "string") return false;
    const typed = text.trim().toLocaleLowerCase();
    return typed.length > 0 && [title.title, title.originalTitle].some((name) => (name || "").trim().toLocaleLowerCase() === typed);
}

function answer(ctx, uid, msg, isGuess) {
    const { state, now } = ctx;
    if (state.pause) return fail(ctx, uid, "paused", "The room is paused");
    if (state.phase !== "playing" && state.phase !== "countdown") return fail(ctx, uid, "bad_phase", "No film is running");

    const film = state.match.film;
    const entry = film.participants[uid];
    if (!entry || entry.status !== "thinking") return;
    if (now < film.startedAt || now < film.blockedUntil) return fail(ctx, uid, "not_started", "The film has not started yet");
    if (msg.film !== film.index + 1 || msg.frame !== entry.frame) {
        // A repeat after a reconnect or a double tap: say where things stand.
        return tell(ctx, uid, snapshot(state, uid, now));
    }

    const title = state.match.films[film.index];
    const correct = isGuess && ((Number(msg.tmdbId) === title.tmdbId && msg.mediaType === title.mediaType)
        || namesTitle(msg.text, title));

    if (isGuess) tell(ctx, uid, { t: "guessResult", film: film.index + 1, frame: entry.frame, correct });

    if (correct) {
        entry.status = "solved";
        entry.solvedAtFrame = entry.frame;
        entry.ms = Math.max(0, now - film.startedAt);
        entry.points = filmPoints(state.settings, entry.frame, entry.ms);
        if (film.firstCorrectAt === null) {
            film.firstCorrectAt = now;
            const cut = now + state.settings.afterFirstCorrectSec * 1000;
            if (cut < film.deadline) {
                film.deadline = cut;
                broadcast(ctx, { t: "deadline", film: film.index + 1, endsInMs: cut - now });
            }
        }
    } else if (entry.frame >= state.settings.frames) {
        entry.status = "failed";
    } else {
        entry.frame += 1;
    }

    broadcast(ctx, { t: "progress", uid, film: film.index + 1, frame: entry.frame, status: entry.status });
    checkFilmEnd(ctx);
}

function checkFilmEnd(ctx) {
    const { state } = ctx;
    const film = state.match?.film;
    if (!film || state.phase !== "playing") return;
    const waiting = Object.entries(film.participants)
        .some(([uid, entry]) => entry.status === "thinking" && state.players[uid] && !state.players[uid].left);
    if (!waiting) endFilm(ctx);
}

function endFilm(ctx) {
    const { state, now } = ctx;
    const match = state.match;
    const film = match.film;
    const title = match.films[film.index];
    const filmNumber = film.index + 1;

    const results = Object.entries(film.participants).map(([uid, entry]) => ({
        uid,
        solvedAtFrame: entry.solvedAtFrame,
        ms: entry.ms,
        points: entry.points
    }));

    let duel = null;
    if (state.settings.kind === "duel") {
        const multiplier = duelMultiplier(state.settings, filmNumber);
        const damage = {};
        const [a, b] = seatedUids(state);
        const points = (uid) => results.find((result) => result.uid === uid)?.points ?? 0;
        const gap = points(a) - points(b);
        const loser = gap > 0 ? b : a;
        damage[a] = 0;
        damage[b] = 0;
        if (gap !== 0) {
            damage[loser] = Math.round(Math.abs(gap) * multiplier);
            state.players[loser].hp = Math.max(0, state.players[loser].hp - damage[loser]);
        }
        duel = { multiplier, damage, hp: { [a]: state.players[a].hp, [b]: state.players[b].hp } };
    } else {
        for (const result of results) if (state.players[result.uid]) state.players[result.uid].total += result.points;
    }

    match.results.push({ film: filmNumber, results });
    state.played[title.mediaKey] = now;
    const remembered = Object.entries(state.played).sort((x, y) => y[1] - x[1]).slice(0, PLAYED_MEMORY);
    state.played = Object.fromEntries(remembered);

    const last = filmNumber >= match.films.length;
    const knockout = duel && Object.values(duel.hp).some((hp) => hp <= 0);
    const done = last || knockout;

    match.lastReveal = {
        film: filmNumber,
        answer: answerOf(title),
        results,
        standings: standings(state),
        ...(duel ? { duel } : {}),
        nextInMs: done ? 0 : state.settings.revealSec * 1000
    };
    broadcast(ctx, { t: "reveal", ...match.lastReveal });

    if (done) {
        if (duel) {
            const [a, b] = seatedUids(state);
            const hpA = state.players[a].hp;
            const hpB = state.players[b].hp;
            if (hpA === hpB) return finish(ctx, "draw", null);
            return finish(ctx, knockout ? "knockout" : "films_done", hpA > hpB ? a : b);
        }
        return finish(ctx, "films_done", null);
    }

    match.film = newFilm(film.index + 1);
    match.revealEndsAt = now + state.settings.revealSec * 1000;
    match.readyDeadline = match.revealEndsAt + state.settings.readyTimeoutSec * 1000;
    state.phase = "reveal";
    broadcast(ctx, prepareMessage(state));
}

function seatedUids(state) {
    return Object.values(state.players).sort(byJoin).map((player) => player.uid);
}

function answerOf(title) {
    return {
        mediaKey: title.mediaKey,
        tmdbId: title.tmdbId,
        mediaType: title.mediaType,
        title: title.title,
        originalTitle: title.originalTitle,
        year: title.year,
        posterPath: title.posterPath
    };
}

export function standings(state) {
    const players = Object.values(state.players);
    if (state.settings.kind === "duel") {
        return players.sort((a, b) => b.hp - a.hp || byJoin(a, b)).map((player, i, all) => ({
            uid: player.uid,
            place: all.findIndex((other) => other.hp === player.hp) + 1,
            hp: player.hp
        }));
    }
    return players.sort((a, b) => b.total - a.total || byJoin(a, b)).map((player, i, all) => ({
        uid: player.uid,
        place: all.findIndex((other) => other.total === player.total) + 1,
        total: player.total
    }));
}

function finishedFilms(state) {
    if (!state.match) return [];
    return state.match.results.map((entry) => ({
        film: entry.film,
        answer: answerOf(state.match.films[entry.film - 1]),
        frames: state.match.films[entry.film - 1].frames,
        results: entry.results
    }));
}

function finish(ctx, reason, winnerUid) {
    const { state, now } = ctx;
    state.phase = "finished";
    state.finishedAt = now;
    state.pause = null;
    state.newMatchVotes = [];
    state.finished = { reason, winnerUid, standings: standings(state), films: finishedFilms(state) };
    broadcast(ctx, { t: "finished", ...state.finished });
}

function forfeit(ctx, loserUid) {
    const winner = seatedUids(ctx.state).find((uid) => uid !== loserUid) ?? null;
    finish(ctx, "forfeit", winner);
}

function frameBroken(ctx, uid, msg) {
    const { state } = ctx;
    if (state.phase !== "ready" && state.phase !== "reveal") return;
    if (msg.film !== state.match.film.index + 1) return;
    const film = state.match.films[state.match.film.index];
    if (!Number.isInteger(msg.index) || msg.index < 0 || msg.index >= film.frames.length) {
        return fail(ctx, uid, "bad_message", "No such frame");
    }
    if (!film.spares.length) return fail(ctx, uid, "no_spare", "No spare frame left");
    // The same substitute for everyone, and everyone loads again.
    film.frames[msg.index] = film.spares.shift();
    state.match.film.readyUids = [];
    broadcast(ctx, prepareMessage(state));
}

// ------------------------------------------------------------------ pause

function phaseDeadline(state) {
    const match = state.match;
    if (!match) return null;
    if (state.phase === "countdown" || state.phase === "playing") return match.film.deadline;
    if (state.phase === "reveal") return match.revealEndsAt;
    if (state.phase === "ready") return match.readyDeadline;
    return null;
}

function pause(ctx, uid) {
    const { state, now } = ctx;
    if (state.pause) return;
    if (!PAUSABLE_PHASES.includes(state.phase)) return fail(ctx, uid, "bad_phase", "Nothing to pause");
    state.pause = { at: now, autoResumeAt: now + state.settings.pauseMaxSec * 1000 };
    broadcast(ctx, { t: "paused", remainingMs: Math.max(0, (phaseDeadline(state) ?? now) - now), autoResumeInMs: state.settings.pauseMaxSec * 1000 });
}

// Every clock of the match moves on by the pause, plus a fresh 3-2-1 when a
// film is running, and the pause never reaches anyone's time.
function resume(ctx) {
    const { state, now } = ctx;
    const match = state.match;
    const running = state.phase === "countdown" || state.phase === "playing";
    const countdown = running ? state.settings.countdownSec * 1000 : 0;
    const shift = now - state.pause.at + countdown;
    state.pause = null;

    if (match) {
        const film = match.film;
        if (film.startedAt !== null) film.startedAt += shift;
        if (film.deadline !== null) film.deadline += shift;
        if (running) film.blockedUntil = now + countdown;
        if (match.revealEndsAt !== null) match.revealEndsAt += shift;
        if (match.readyDeadline !== null) match.readyDeadline += shift;
    }
    broadcast(ctx, { t: "resumed", startsInMs: countdown });
}

// ------------------------------------------------------------------ time

function forfeitAt(state, player) {
    if (state.settings.kind !== "duel" || !MATCH_PHASES.includes(state.phase) || player.absentSince === null) return null;
    return player.absentSince + state.settings.forfeitSec * 1000;
}

// Runs whatever came due, in order, until nothing more does. Called before and
// after every event, so a late alarm or none at all changes nothing.
function advance(ctx) {
    const { state, now } = ctx;
    if (state.phase === "closed") return;

    for (let guard = 0; guard < 50; guard += 1) {
        if (!step(ctx)) break;
    }

    if (state.settings.kind === "room" && state.hostAbsentSince !== null
        && now >= state.hostAbsentSince + state.settings.hostGraceSec * 1000) {
        transferHost(ctx);
    }
    if (state.settings.kind === "room" && state.hostUid && !state.players[state.hostUid]) transferHost(ctx);

    const idle = state.settings.idleCleanupSec * 1000;
    const empty = !Object.values(state.players).some((player) => player.connection !== "offline");
    if ((state.finishedAt !== null && now >= state.finishedAt + idle) || (empty && state.emptySince !== null && now >= state.emptySince + idle)) {
        state.phase = "closed";
        ctx.effects.push({ type: "destroy" });
    }
}

function step(ctx) {
    const { state, now } = ctx;

    for (const player of Object.values(state.players)) {
        if (player.transport === "poll" && player.connection !== "offline" && now - player.lastPollAt > POLL_STALE_MS) {
            goneQuiet(ctx, player.uid, player.lastPollAt + POLL_STALE_MS);
            return true;
        }
    }

    if (state.settings.kind === "duel" && MATCH_PHASES.includes(state.phase)) {
        const due = Object.values(state.players).filter((player) => {
            const at = forfeitAt(state, player);
            return at !== null && now >= at;
        });
        if (due.length === 2) {
            finish(ctx, "abandoned", null);
            return true;
        }
        if (due.length === 1) {
            forfeit(ctx, due[0].uid);
            return true;
        }
    }

    if (state.pause) {
        if (now >= state.pause.autoResumeAt) {
            resume(ctx);
            return true;
        }
        return false;
    }

    const match = state.match;
    switch (state.phase) {
        case "countdown":
            if (now >= match.film.startedAt) {
                state.phase = "playing";
                return true;
            }
            return false;
        case "playing":
            if (now >= match.film.deadline) {
                endFilm(ctx);
                return true;
            }
            return false;
        case "reveal":
            if (now >= match.revealEndsAt) {
                state.phase = "ready";
                if (everyoneReady(state)) startCountdown(ctx);
                return true;
            }
            return false;
        case "ready":
            if (now >= match.readyDeadline) {
                startCountdown(ctx);
                return true;
            }
            return false;
        default:
            return false;
    }
}

export function nextAlarm(state) {
    if (state.phase === "closed") return null;
    const times = [];

    for (const player of Object.values(state.players)) {
        if (player.transport === "poll" && player.connection !== "offline") times.push(player.lastPollAt + POLL_STALE_MS + 1);
        const forfeitTime = forfeitAt(state, player);
        if (forfeitTime !== null) times.push(forfeitTime);
    }

    if (state.pause) {
        times.push(state.pause.autoResumeAt);
    } else {
        const deadline = phaseDeadline(state);
        if (deadline !== null) times.push(deadline);
    }

    if (state.settings.kind === "room" && state.hostAbsentSince !== null
        && present(state).some((player) => player.uid !== state.hostUid)) {
        times.push(state.hostAbsentSince + state.settings.hostGraceSec * 1000);
    }

    const idle = state.settings.idleCleanupSec * 1000;
    if (state.finishedAt !== null) times.push(state.finishedAt + idle);
    if (state.emptySince !== null) times.push(state.emptySince + idle);

    return times.length ? Math.min(...times) : null;
}

// ------------------------------------------------------------------ snapshot

// The whole room as one player may see it: enough to redraw any screen after a
// reconnect without replaying what was missed.
export function snapshot(state, uid, now) {
    const match = state.match;
    const player = state.players[uid];
    const result = {
        t: "snapshot",
        seq: state.seq,
        phase: state.phase,
        code: state.code,
        you: uid,
        hostUid: state.hostUid,
        settings: publicSettings(state.settings),
        players: Object.values(state.players).sort(byJoin).map((p) => publicPlayer(state, p, now)),
        film: null,
        prepare: null,
        paused: state.pause
            ? { remainingMs: Math.max(0, (phaseDeadline(state) ?? state.pause.at) - state.pause.at), autoResumeInMs: Math.max(0, state.pause.autoResumeAt - now) }
            : null,
        standings: standings(state),
        lastReveal: match?.lastReveal ?? null,
        finished: state.phase === "finished" ? state.finished : null
    };

    if (match && (state.phase === "countdown" || state.phase === "playing")) {
        const film = match.film;
        const mine = film.participants[uid];
        const frozenNow = state.pause ? state.pause.at : now;
        result.film = {
            index: film.index + 1,
            total: match.films.length,
            progress: Object.entries(film.participants).map(([id, entry]) => ({ uid: id, frame: entry.frame, status: entry.status })),
            startsInMs: Math.max(0, Math.max(film.startedAt, film.blockedUntil) - frozenNow),
            endsInMs: Math.max(0, film.deadline - frozenNow)
        };
        // Frames only to someone playing this film: a late arrival sits it out.
        if (mine) {
            const title = match.films[film.index];
            Object.assign(result.film, { frames: title.frames, spares: title.spares, yourFrame: mine.frame, yourStatus: mine.status });
        }
    }

    if (match && (state.phase === "ready" || state.phase === "reveal") && player && !player.left) {
        result.prepare = { ...prepareMessage(state), ready: match.film.readyUids.includes(uid) };
        delete result.prepare.t;
    }

    if (state.settings.kind === "duel" && match) {
        result.duel = {
            hp: Object.fromEntries(Object.values(state.players).map((p) => [p.uid, p.hp])),
            multiplier: duelMultiplier(state.settings, (match.film?.index ?? 0) + 1)
        };
    }
    return result;
}
