// PvP checks: the rules in src/pvp/core.js driven directly with a hand-moved
// clock, then the routes and the room object through the shim, then whole
// matches played by the bots. Called from run.mjs.

const API = new URL("..", import.meta.url).pathname;

const core = await import(`${API}src/pvp/core.js`);
const { CONFIG_DEFAULTS } = await import(`${API}src/lib/config.js`);
const names = await import(`${API}src/lib/pvpNames.js`);
const { mintTicket, readTicket } = await import(`${API}src/lib/pvpTicket.js`);
const { verifyJWT, signJWT } = await import(`${API}src/lib/crypto.js`);
const { chooseKeys, loadMatchFilms } = await import(`${API}src/pvp/films.js`);
const { seededRandom } = await import(`${API}src/lib/frames.js`);
const { localServer, playMatch, seedStatements } = await import(`${API}tools/pvp-bots.mjs`);

const T0 = Date.UTC(2026, 9, 30, 12);
const SEC = 1000;

// ------------------------------------------------------------------ fixtures

function fixtureFilms(count = 3, frames = 6) {
    return Array.from({ length: count }, (_, i) => ({
        mediaKey: `movie_${i + 1}`,
        tmdbId: i + 1,
        mediaType: "movie",
        title: `Secret Title ${i + 1}`,
        originalTitle: `Secret Title ${i + 1}`,
        year: 2000 + i,
        posterPath: `/poster${i + 1}.jpg`,
        frames: Array.from({ length: frames }, (_, f) => ({ path: `/f${i + 1}-${f}.jpg`, width: 1920, height: 1080 })),
        spares: [{ path: `/s${i + 1}-0.jpg`, width: 1920, height: 1080 }]
    }));
}

class Table {
    constructor(kind = "room", { films = 3, config = {} } = {}) {
        this.settings = core.buildSettings({ ...CONFIG_DEFAULTS, ...config }, { kind, mediaType: "movie", films, frames: 6, timeLimitSec: 30 });
        this.state = core.createRoom({ code: "123456", settings: this.settings, createdBy: "a", now: T0 });
        this.now = T0;
        this.log = [];
        this.effects = [];
        this.closes = [];
    }

    at(seconds) {
        this.now = T0 + seconds * SEC;
        return this;
    }

    run(event) {
        const result = core.reduce(this.state, event, this.now);
        this.log.push(...result.out);
        this.effects.push(...result.effects);
        this.closes.push(...result.closes);
        this.last = result;
        return result;
    }

    join(uid, extra = {}) {
        return this.run({
            type: "connect",
            via: "ticket",
            ticket: { uid, code: "123456", name: extra.name ?? `Player_${uid}`, alias: `Alias_${uid}`, icon: "star", color: "red", exp: this.now + 60 * SEC, mac: `mac-${uid}-${this.now}-${this.log.length}` },
            resumeToken: `resume-${uid}`
        });
    }

    send(uid, msg) {
        return this.run({ type: "message", uid, msg });
    }

    tick() {
        return this.run({ type: "tick" });
    }

    film() {
        return this.state.match.film.index + 1;
    }

    sent(t, to) {
        return this.log.filter((entry) => entry.msg.t === t && (to === undefined || entry.to === to || entry.to === null)).map((entry) => entry.msg);
    }

    lastSent(t, to) {
        return this.sent(t, to).at(-1);
    }

    // Start → films → everyone ready → countdown → playing.
    startMatch(host, films = fixtureFilms(this.settings.films)) {
        if (this.settings.kind === "room") this.send(host, { t: "start" });
        this.run({ type: "filmsLoaded", films });
        return this;
    }

    readyAll(uids) {
        for (const uid of uids) this.send(uid, { t: "ready", film: this.film() });
        return this;
    }

    guess(uid, tmdbId) {
        const entry = this.state.match.film.participants[uid];
        return this.send(uid, { t: "guess", film: this.film(), frame: entry.frame, tmdbId, mediaType: "movie" });
    }
}

export async function runPvpTests(check) {
    console.log("\npvp");

    // -------------------------------------------------------------- scoring
    {
        const settings = core.buildSettings(CONFIG_DEFAULTS, { kind: "room", mediaType: "movie", films: 5, frames: 6, timeLimitSec: 45 });
        let ordered = true;
        for (let frame = 1; frame < 6; frame += 1) {
            if (core.filmPoints(settings, frame, 44.9 * SEC) <= core.filmPoints(settings, frame + 1, 0)) ordered = false;
        }
        check("score: any answer on a frame beats any answer on the next one", ordered);
        check("score: first frame instantly is 1000", core.filmPoints(settings, 1, 0) === 1000);
        check("score: past the limit only the frame counts", core.filmPoints(settings, 2, 60 * SEC) === 750);
        check("score: time counts in fractions of a second", core.filmPoints(settings, 1, 5 * SEC) !== core.filmPoints(settings, 1, 6 * SEC));
        check("duel multiplier: ×1 up to film 3, then +0.5 a film",
            [1, 2, 3, 4, 5, 6].map((n) => core.duelMultiplier(settings, n)).join(",") === "1,1,1,1.5,2,2.5");
    }

    // -------------------------------------------------------------- codes, names, tickets
    {
        const random = seededRandom(9);
        const codes = Array.from({ length: 200 }, () => core.randomRoomCode(random));
        check("room codes: six digits", codes.every((code) => /^[0-9]{6}$/.test(code) && core.isRoomCode(code)));
        check("room codes: every digit turns up, zero and one too", new Set(codes.join("")).size === 10);
        check("room codes: wrong length or other characters are not a code",
            !core.isRoomCode("12345") && !core.isRoomCode("1234567") && !core.isRoomCode("12 456") && !core.isRoomCode("abcdef") && !core.isRoomCode(123456));

        const generated = Array.from({ length: 500 }, (_, i) => names.generateName(i));
        check("names: generated ones fit 16 and pass the filter", generated.every((name) => name.length <= 16 && /^[A-Za-z0-9_]+$/.test(name) && names.isCleanName(name)));
        check("names: generated ones vary", new Set(generated).size > 300);
        const rejects = (value) => {
            try {
                names.validateName(value);
                return false;
            } catch (error) {
                return true;
            }
        };
        check("names: Cyrillic, spaces, too short and too long are refused", ["Кино", "Noir Gaffer", "ab", "A".repeat(17)].every(rejects));
        check("names: obscenities are refused through look-alike digits", ["Fuck3r", "sh1tReel", "xu1Boss", "P1zdec", "my_huy"].every(rejects));
        check("names: ordinary film words pass", ["Hitchcock", "ClassicReel", "Bassist", "Cocktail_Usher"].every((name) => !rejects(name)));
        check("names: a duplicate gets _2 and stays within 16",
            names.dedupeName("MidnightProjecti", ["midnightprojecti"]) === "MidnightProjec_2"
            && names.dedupeName("Noir", ["Noir", "Noir_2"]) === "Noir_3");

        const profile = names.pvpProfile("uid-1");
        check("profile: derived from the uid with no row", profile.name === names.pvpProfile("uid-1").name && !profile.customName && profile.alias !== profile.name);
        check("profile: a reroll changes the generated name", names.pvpProfile("uid-1", { name: null, name_seed: 1 }).name !== profile.name);

        const env = { JWT_SECRET: "test-secret-test-secret-test-secret-00" };
        const ticket = await mintTicket(env, { uid: "u1", code: "123456", name: "Noir", alias: "Pale", icon: "star", color: "red" }, { now: T0 });
        check("ticket: reads back in its room", (await readTicket(env, ticket, "123456", { now: T0 + 30 * SEC }))?.uid === "u1");
        check("ticket: refused in another room", (await readTicket(env, ticket, "654321", { now: T0 })) === null);
        check("ticket: refused after a minute", (await readTicket(env, ticket, "123456", { now: T0 + 61 * SEC })) === null);
        const [prefix, body, mac] = ticket.split(".");
        const forged = `${prefix}.${body.slice(0, -2)}AA.${mac}`;
        check("ticket: a changed payload is refused", (await readTicket(env, forged, "123456", { now: T0 })) === null);
        check("ticket: is not an access token", (await verifyJWT(ticket, env.JWT_SECRET)) === null);
        const jwt = await signJWT({ sub: "u1", code: "123456", exp: T0 }, env.JWT_SECRET, 60);
        check("ticket: an access token is not a ticket", (await readTicket(env, jwt, "123456", { now: T0 })) === null);
    }

    // -------------------------------------------------------------- a room, step by step
    {
        const table = new Table("room");
        table.join("a");
        table.at(1).join("b");
        table.at(2).join("c");
        check("room: the creator is the host", table.state.hostUid === "a");
        check("room: welcome comes first, with a resume token and a snapshot",
            table.last.out[0].msg.t === "welcome" && table.last.out[0].msg.you.resumeToken === "resume-c" && table.last.out[0].msg.snapshot.players.length === 3);

        table.send("b", { t: "start" });
        check("room: only the host starts", table.lastSent("error", "b")?.code === "not_host" && table.state.phase === "lobby");
        table.send("a", { t: "settings", films: 7 });
        check("room: settings outside the choices are refused", table.lastSent("error", "a")?.code === "bad_message");
        table.send("a", { t: "settings", films: 5, timeLimitSec: 45 });
        check("room: the host changes settings in the lobby", table.state.settings.films === 5 && table.lastSent("settings").settings.timeLimitSec === 45);
        table.send("a", { t: "settings", timeLimitSec: 30 });
        check("room: settings tell clients how many seats there are",
            table.lastSent("settings").settings.maxPlayers === CONFIG_DEFAULTS.pvpRoomMaxPlayers);
        check("room: the snapshot carries the seat count", core.snapshot(table.state, "a", table.now).settings.maxPlayers === 8);
        check("duel: two seats", core.snapshot(new Table("duel").state, "a", T0).settings.maxPlayers === 2);

        table.at(5).send("a", { t: "start" });
        check("room: start asks for the films", table.state.phase === "loading" && table.effects.at(-1).type === "loadFilms" && table.effects.at(-1).count === 5);
        // The pool had only three: the match is three films long.
        table.run({ type: "filmsLoaded", films: fixtureFilms(3) });
        check("room: films → prepare for everyone", table.state.phase === "ready" && table.lastSent("prepare").frames.length === 6);
        const beforeReveal = JSON.stringify(table.log);
        check("room: no title leaves the server before its reveal", !beforeReveal.includes("Secret Title"));

        table.at(6).readyAll(["a", "b"]);
        check("room: waits for everyone online", table.state.phase === "ready");
        table.send("c", { t: "ready", film: 1 });
        const countdown = table.lastSent("countdown");
        check("room: all ready → 3-2-1", table.state.phase === "countdown" && countdown.startsInMs === 3000 && countdown.participants.length === 3);

        table.at(7).guess("a", 1);
        check("room: an answer during the countdown is refused", table.lastSent("error", "a")?.code === "not_started");

        // The film started at 9 s.
        table.at(11).guess("b", 99);
        check("room: a wrong answer opens the next frame", table.state.match.film.participants.b.frame === 2
            && table.lastSent("guessResult", "b").correct === false && table.lastSent("progress").frame === 2);
        check("room: others see the frame, never the answer", !JSON.stringify(table.lastSent("progress")).includes("99"));
        table.send("b", { t: "guess", film: 1, frame: 1, tmdbId: 1, mediaType: "movie" });
        check("room: a stale frame is answered with a snapshot, not counted", table.lastSent("snapshot", "b") && table.state.match.film.participants.b.status === "thinking");

        table.at(14).guess("a", 1);
        const a = table.state.match.film.participants.a;
        check("room: the right film by tmdbId scores frame plus time", a.status === "solved" && a.ms === 5000 && a.points === 900 + Math.round(100 * (1 - 5 / 30)));
        check("room: the first right answer cuts everyone to 15 s", table.state.match.film.deadline === T0 + 29 * SEC && table.lastSent("deadline").endsInMs === 15000);
        table.send("c", { t: "guess", film: 1, frame: 1, tmdbId: 1, mediaType: "tv" });
        check("room: same id as a show is not the film", table.state.match.film.participants.c.frame === 2);

        table.at(20).send("b", { t: "skip", film: 1, frame: 2 });
        check("room: a skip opens the next frame too", table.state.match.film.participants.b.frame === 3);

        // Nobody else answers: the cut deadline ends the film.
        table.at(29).tick();
        const reveal = table.lastSent("reveal");
        check("room: the deadline ends the film with the reveal", reveal.film === 1 && reveal.answer.title === "Secret Title 1" && table.state.phase === "reveal");
        check("room: points only for the right answer", reveal.results.find((r) => r.uid === "a").points === a.points
            && reveal.results.filter((r) => r.uid !== "a").every((r) => r.points === 0));
        check("room: the next film is prepared during the reveal", table.lastSent("prepare").film === 2);

        // Film 2: two ready during the reveal, c never loads.
        table.at(30).readyAll(["a", "b"]);
        check("room: ready during the reveal does not cut it short", table.state.phase === "reveal");
        table.at(37).tick();
        check("room: after the reveal, waits for the slow one", table.state.phase === "ready");
        table.at(67).tick();
        check("room: after the ready timeout the film starts without them", table.state.phase === "countdown"
            && table.lastSent("countdown").participants.join() === "a,b");
        const snapC = core.snapshot(table.state, "c", table.now);
        check("room: someone sitting out gets progress but no frames", snapC.film && !snapC.film.frames && snapC.film.progress.length === 2);
        const resultsForC = table.sent("guessResult", "c").length;
        table.at(70).send("c", { t: "guess", film: 2, frame: 1, tmdbId: 2, mediaType: "movie" });
        check("room: and cannot answer", !table.state.match.film.participants.c && table.sent("guessResult", "c").length === resultsForC);

        // Pause in the middle of film 2 (started at 70 s).
        table.at(75).send("b", { t: "pause" });
        check("room: only the host pauses", table.lastSent("error", "b").code === "not_host");
        table.send("a", { t: "pause" });
        check("room: pause", table.state.pause && table.lastSent("paused").remainingMs === 25000);
        table.at(80).guess("b", 2);
        check("room: no answers while paused", table.lastSent("error", "b").code === "paused");
        table.at(200).tick();
        check("room: the film does not end while paused", table.state.phase === "playing");
        table.send("a", { t: "kick", uid: "c" });
        check("room: the host kicks during a pause", !table.state.players.c && table.state.kicked.includes("c")
            && table.closes.at(-1).uid === "c" && table.closes.at(-1).code === 4003);
        table.at(260).send("a", { t: "resume" });
        check("room: resume with a fresh 3-2-1", !table.state.pause && table.lastSent("resumed").startsInMs === 3000);
        table.at(261).guess("b", 2);
        check("room: answers wait out the resume countdown", table.lastSent("error", "b").code === "not_started");
        table.at(265).guess("b", 2);
        const b = table.state.match.film.participants.b;
        // 5 s before the pause, then 2 s after the resume countdown.
        check("room: paused time is not anyone's time", b.ms === 7000);
        table.at(266).guess("a", 2);
        check("room: everyone answered → reveal at once", table.state.phase === "reveal" && table.lastSent("reveal").film === 2);
        check("room: the kicked player is gone from the table", !table.lastSent("reveal").standings.some((row) => row.uid === "c"));

        const kickedJoin = table.join("c");
        check("room: a kicked player cannot come back", kickedJoin.reply.error === "kicked");

        // Film 3: a new player walks in mid-film.
        table.at(267).readyAll(["a", "b"]);
        table.at(275).tick();
        table.at(279).join("d");
        check("room: someone joining mid-film sits it out", table.state.players.d && !table.state.match.film.participants.d
            && !core.snapshot(table.state, "d", table.now).film.frames);

        // a drops and comes back within the film: carries on from the same frame.
        table.at(280).guess("a", 99);
        table.run({ type: "disconnect", uid: "a" });
        check("room: a dropped player is offline to others", table.lastSent("player").player.connection === "offline");
        table.at(285).run({ type: "connect", via: "resume", token: "resume-a", lastSeq: 0 });
        const back = table.last.out[0].msg.snapshot;
        check("room: back in the same film, same frame, with the frames", back.film.frames.length === 6 && back.film.yourFrame === 2);
        table.run({ type: "connect", via: "resume", token: "resume-a", lastSeq: table.state.seq });
        check("room: up to date → welcome without a snapshot", table.last.out[0].msg.t === "welcome" && !table.last.out[0].msg.snapshot);

        table.at(286).guess("a", 3);
        table.at(287).guess("b", 3);
        const finished = table.lastSent("finished");
        check("room: the last film ends the match", table.state.phase === "finished" && finished.reason === "films_done");
        check("room: standings by total, all three films with frames", finished.standings[0].total >= finished.standings[1].total
            && finished.films.length === 3 && finished.films.every((film) => film.frames.length === 6 && film.answer.title));
        check("room: the summary survives in the snapshot", core.snapshot(table.state, "b", table.now).finished.films.length === 3);

        table.send("a", { t: "kick", uid: "b" });
        check("room: kicking on the final screen rewrites the result", !table.lastSent("finished").standings.some((row) => row.uid === "b")
            && table.lastSent("finished").films.every((film) => !film.results.some((r) => r.uid === "b")));

        table.send("a", { t: "newMatch" });
        check("room: a new match goes back to the lobby", table.state.phase === "lobby" && !table.state.match && table.state.finished === null
            && Object.values(table.state.players).every((p) => p.total === 0 && !p.ready));
    }

    // -------------------------------------------------------------- host
    {
        const table = new Table("room");
        table.join("a");
        table.at(1).join("b");
        table.at(2).join("c");
        table.at(3).send("a", { t: "leave" });
        check("host: leaving in the lobby hands over in join order", table.state.hostUid === "b" && !table.state.players.a);

        table.at(4).run({ type: "disconnect", uid: "b" });
        table.at(20).tick();
        check("host: not handed over inside the grace", table.state.hostUid === "b");
        check("host: the grace is on the alarm", core.nextAlarm(table.state) === T0 + 34 * SEC);
        table.at(34).tick();
        check("host: handed over after 30 s offline", table.state.hostUid === "c");
        table.at(40).run({ type: "connect", via: "resume", token: "resume-b", lastSeq: 0 });
        check("host: coming back does not take it back", table.state.hostUid === "c");
    }

    // -------------------------------------------------------------- frames, spares
    {
        const table = new Table("room");
        table.join("a");
        table.join("b");
        table.startMatch("a");
        table.send("a", { t: "ready", film: 1 });
        table.send("b", { t: "frameBroken", film: 1, index: 2 });
        const prepare = table.lastSent("prepare");
        check("frames: a broken frame is replaced by the spare for everyone", prepare.frames[2].path === "/s1-0.jpg" && prepare.spares.length === 0);
        check("frames: and everyone loads again", table.state.match.film.readyUids.length === 0);
        table.send("b", { t: "frameBroken", film: 1, index: 3 });
        check("frames: no spare left is said so", table.lastSent("error", "b").code === "no_spare");
    }

    // -------------------------------------------------------------- duel
    {
        const table = new Table("duel", { films: 20 });
        table.join("a");
        table.at(1).join("b");
        check("duel: no host", table.state.hostUid === null);
        check("duel: a third player is refused", table.join("x").reply.error === "room_full");
        table.send("a", { t: "ready", film: 0 });
        check("duel: one ready is not a start", table.state.phase === "lobby");
        table.send("b", { t: "ready", film: 0 });
        check("duel: both ready → match", table.state.phase === "loading" && table.effects.at(-1).count === 20);
        check("duel: nobody joins a running duel", core.joinRefusal(table.state, "x") === "match_running");

        table.run({ type: "filmsLoaded", films: fixtureFilms(20) });
        let t = 2;
        const playFilm = (aAnswers, bAnswers) => {
            table.at(t).readyAll(["a", "b"]);
            if (table.state.phase === "reveal") table.at((t = Math.ceil((table.state.match.revealEndsAt - T0) / SEC))).tick();
            const start = (table.state.match.film.startedAt - T0) / SEC;
            t = start + 1;
            const film = table.film();
            for (const [uid, answers] of [["a", aAnswers], ["b", bAnswers]]) {
                for (const correct of answers) table.at(t).guess(uid, correct ? film : 999);
            }
            table.at(Math.max(t, start + 31)).tick();
            t = (table.now - T0) / SEC + 1;
            return table.sent("reveal").at(-1);
        };

        let reveal = playFilm([true], [false, false, false, false, false, false]);
        check("duel: the gap is the damage at ×1", reveal.duel.multiplier === 1 && reveal.duel.damage.b === core.filmPoints(table.settings, 1, SEC) && reveal.duel.hp.b === 3000 - reveal.duel.damage.b);
        reveal = playFilm([false, false, false, false, false, false], [false, false, false, false, false, false]);
        check("duel: both miss → no damage", reveal.duel.damage.a === 0 && reveal.duel.damage.b === 0);
        playFilm([false, false, false, false, false, false], [false, false, false, false, false, false]);
        reveal = playFilm([true], [false, true]);
        check("duel: from film 4 the gap is worth ×1.5", reveal.duel.multiplier === 1.5 && reveal.duel.damage.b === Math.round((core.filmPoints(table.settings, 1, SEC) - core.filmPoints(table.settings, 2, SEC)) * 1.5));

        // b minimises the app: the forfeit clock runs, as in chess.
        table.at(t).send("b", { t: "away", away: true });
        const shown = table.lastSent("player").player;
        check("duel: away shows the forfeit countdown", shown.connection === "away" && shown.forfeitInMs === 60000);
        table.at(t + 30).send("b", { t: "away", away: false });
        check("duel: coming back stops it", table.lastSent("player").player.forfeitInMs === undefined);
        table.at(t + 31).run({ type: "disconnect", uid: "b" });
        check("duel: the alarm is set for the forfeit", core.nextAlarm(table.state) <= T0 + (t + 91) * SEC);
        table.at(t + 91).tick();
        const finished = table.lastSent("finished");
        check("duel: 60 s gone → technical defeat", finished.reason === "forfeit" && finished.winnerUid === "a");
    }
    {
        const table = new Table("duel", { films: 20, config: { pvpDuelHP: 1500 } });
        table.join("a");
        table.join("b");
        table.send("a", { t: "ready", film: 0 });
        table.send("b", { t: "ready", film: 0 });
        table.run({ type: "filmsLoaded", films: fixtureFilms(20) });
        table.readyAll(["a", "b"]);
        table.at(4).guess("a", 1);
        table.guess("b", 2);
        table.at(5).send("b", { t: "skip", film: 1, frame: 2 });
        table.at(40).tick();
        table.at(49).readyAll(["a", "b"]);
        table.at(50).tick();
        table.at(53).guess("a", 2);
        for (let i = 0; i < 6; i += 1) table.send("b", { t: "skip", film: 2, frame: table.state.match?.film.participants.b?.frame ?? 6 });
        const finished = table.lastSent("finished");
        check("duel: HP at zero is a knockout", finished?.reason === "knockout" && finished.winnerUid === "a" && finished.standings[1].hp === 0);
        check("duel: the knockout film is revealed too", table.lastSent("reveal").nextInMs === 0);
    }
    {
        const table = new Table("duel", { films: 2 });
        table.state.settings.films = 2;
        table.join("a");
        table.join("b");
        table.send("a", { t: "ready", film: 0 });
        table.send("b", { t: "ready", film: 0 });
        table.run({ type: "filmsLoaded", films: fixtureFilms(2) });
        table.readyAll(["a", "b"]);
        table.at(40).tick();
        table.at(49).readyAll(["a", "b"]);
        table.at(50).tick();
        table.at(90).tick();
        check("duel: films run out with equal HP → draw", table.lastSent("finished")?.reason === "draw");
    }
    {
        const table = new Table("duel");
        table.join("a");
        table.join("b");
        table.send("a", { t: "ready", film: 0 });
        table.send("b", { t: "ready", film: 0 });
        table.run({ type: "filmsLoaded", films: fixtureFilms(20) });
        table.at(1).run({ type: "disconnect", uid: "a" });
        table.at(2).run({ type: "disconnect", uid: "b" });
        table.at(62).tick();
        check("duel: both gone → abandoned", table.lastSent("finished")?.reason === "abandoned");
        table.at(62).send("a", { t: "leave" });
    }
    {
        const table = new Table("duel");
        table.join("a");
        table.join("b");
        table.send("a", { t: "ready", film: 0 });
        table.send("b", { t: "ready", film: 0 });
        table.run({ type: "filmsLoaded", films: fixtureFilms(20) });
        table.at(3).send("b", { t: "leave" });
        check("duel: leaving is a technical defeat at once", table.lastSent("finished")?.reason === "forfeit" && table.lastSent("finished").winnerUid === "a");
        table.send("a", { t: "newMatch" });
        check("duel: a new match needs both", table.state.phase === "finished");
    }

    // -------------------------------------------------------------- flooding
    {
        const table = new Table("room");
        table.join("a");
        table.join("b");
        table.join("c");
        table.startMatch("a");
        table.run({ type: "flood", uid: "b" });
        check("flood: the socket is closed with 4029", table.closes.at(-1).uid === "b" && table.closes.at(-1).code === 4029 && table.state.players.b);
        table.run({ type: "flood", uid: "b" });
        table.run({ type: "flood", uid: "b" });
        check("flood: the third time the player is out of the room", !table.state.players.b && table.state.kicked.includes("b")
            && table.lastSent("playerRemoved").reason === "flood" && table.closes.at(-1).code === 4030);
        check("flood: and cannot come back", table.join("b").reply.error === "kicked"
            && table.run({ type: "connect", via: "resume", token: "resume-b" }).reply.error === "resume_invalid");
        table.run({ type: "flood", uid: "a" });
        table.run({ type: "flood", uid: "a" });
        table.run({ type: "flood", uid: "a" });
        check("flood: a flooding host hands the room over", table.state.hostUid === "c");
    }
    {
        const table = new Table("duel");
        table.join("a");
        table.join("b");
        table.send("a", { t: "ready", film: 0 });
        table.send("b", { t: "ready", film: 0 });
        table.run({ type: "filmsLoaded", films: fixtureFilms(20) });
        for (let i = 0; i < 3; i += 1) table.run({ type: "flood", uid: "b" });
        check("flood: in a duel it is a technical defeat", table.lastSent("finished")?.reason === "forfeit" && table.lastSent("finished").winnerUid === "a"
            && table.run({ type: "connect", via: "resume", token: "resume-b" }).reply.error === "resume_invalid");
    }
    {
        const table = new Table("duel");
        table.join("a");
        table.join("b");
        for (let i = 0; i < 3; i += 1) table.run({ type: "flood", uid: "b" });
        check("flood: in a duel's lobby the seat is freed", !table.state.players.b && core.joinRefusal(table.state, "x") === null);
    }

    // -------------------------------------------------------------- poll, cleanup, tickets
    {
        const table = new Table("room");
        table.join("a");
        table.join("b");
        check("tickets: one use only", table.run({
            type: "connect", via: "ticket", resumeToken: "x",
            ticket: { uid: "a", code: "123456", name: "A", alias: "B", icon: "star", color: "red", exp: T0 + 60 * SEC, mac: table.state.usedTickets && Object.keys(table.state.usedTickets)[0] }
        }).reply.error === "ticket_used");
        check("resume: an unknown token is refused", table.run({ type: "connect", via: "resume", token: "nope" }).reply.error === "resume_invalid");

        table.startMatch("a");
        table.at(1).run({ type: "poll", token: "resume-b", lastSeq: -1, send: [{ t: "ready", film: 1 }] });
        const first = table.last.reply;
        check("poll: answered with a snapshot and the message taken at once", first.messages.at(-1).t === "snapshot"
            && table.state.match.film.readyUids.includes("b") && table.state.players.b.transport === "poll");
        table.send("a", { t: "ready", film: 1 });
        table.at(5).run({ type: "poll", token: "resume-b", lastSeq: first.messages.at(-1).seq, send: [] });
        check("poll: a newer seq brings a fresh snapshot", table.last.reply.messages.at(-1).phase === "playing");
        table.at(6).run({ type: "poll", token: "resume-b", lastSeq: table.state.seq, send: [{ t: "guess", film: 1, frame: 1, tmdbId: 5, mediaType: "movie" }] });
        check("poll: a private answer waits in the outbox", table.last.reply.messages.some((m) => m.t === "guessResult" && m.correct === false));
        table.at(17).tick();
        check("poll: quiet for 10 s → offline", table.state.players.b.connection === "offline");
    }
    {
        const table = new Table("room");
        table.join("a");
        table.at(1).run({ type: "disconnect", uid: "a" });
        check("cleanup: an empty room is on the alarm", core.nextAlarm(table.state) === T0 + 601 * SEC);
        table.at(601).tick();
        check("cleanup: an empty room destroys itself", table.state.phase === "closed" && table.effects.at(-1).type === "destroy");
    }

    // -------------------------------------------------------------- film choice
    {
        const random = seededRandom(4);
        const keys = ["k1", "k2", "k3", "k4", "k5", "k6"];
        const fresh = chooseKeys(keys, { k1: 10, k2: 20 }, 3, random);
        check("films: fresh ones first", fresh.every((key) => !["k1", "k2"].includes(key)));
        const played = { k1: 10, k2: 20, k3: 30, k4: 40, k5: 50, k6: 60 };
        const replay = chooseKeys(keys, played, 3, random);
        check("films: all played → the older half first", replay.every((key) => ["k1", "k2", "k3"].includes(key)));
        check("films: never shorter than the pool allows", chooseKeys(keys, played, 6, random).length === 6);
    }

    // -------------------------------------------------------------- routes and room object
    {
        const server = await localServer({ films: 12 });
        const { api, db, clock, namespace } = server;
        db.exec("INSERT INTO media_items (key, tmdb_id, media_type, title, original_title, status, approved_images, published, created_at) VALUES ('tv_5', 5, 'tv', 'Show', 'Show', 'approved', 9, 1, 0)");
        const today = new Date(clock.now()).toISOString().slice(0, 10);
        db.exec(`INSERT INTO daily_overrides (date, media_key, created_at) VALUES ('${today}', 'movie_70000', 0)`);

        const signIn = async (seed) => (await api.request("POST", "/v1/auth/anonymous", { deviceSecret: seed.padEnd(43, "z") })).body.accessToken;
        const host = await signIn("host");
        const guest = await signIn("guest");

        const profile = await api.request("GET", "/v1/pvp/profile", undefined, host);
        check("route: profile without a row costs no write", profile.status === 200 && profile.body.name
            && db.db.prepare("SELECT COUNT(*) AS n FROM pvp_profiles").get().n === 0);
        const renamed = await api.request("PATCH", "/v1/pvp/profile", { name: "NoirGaffer", icon: "clapper" }, host);
        check("route: a custom name and icon", renamed.body.name === "NoirGaffer" && renamed.body.icon === "clapper" && renamed.body.customName);
        const bad = await api.request("PATCH", "/v1/pvp/profile", { name: "Fuck_it" }, host);
        check("route: a rude name is refused", bad.status === 400 && bad.body.error === "name_rejected");
        const reroll = await api.request("PATCH", "/v1/pvp/profile", { reroll: true }, guest);
        check("route: reroll gives a generated name", reroll.status === 200 && !reroll.body.customName);
        const badIcon = await api.request("PATCH", "/v1/pvp/profile", { icon: "skull" }, guest);
        check("route: an unknown icon is refused", badIcon.status === 400);

        const tv = await api.request("POST", "/v1/pvp/rooms", { kind: "room", mediaType: "tv" }, host);
        check("route: shows are off in PvP by default", tv.status === 400 && tv.body.error === "media_type_disabled");
        const badFilms = await api.request("POST", "/v1/pvp/rooms", { kind: "room", mediaType: "movie", films: 7 }, host);
        check("route: films outside the choices are refused", badFilms.status === 400);
        const noAuth = await api.request("POST", "/v1/pvp/rooms", { kind: "room", mediaType: "movie" });
        check("route: creating a room needs an account", noAuth.status === 401);

        const created = await api.request("POST", "/v1/pvp/rooms", { kind: "room", mediaType: "movie", films: 5 }, host);
        const code = created.body.code;
        check("route: a room is created with a ticket and a socket URL", created.status === 201 && core.isRoomCode(code)
            && created.body.ticket.startsWith("pvp1.") && created.body.socketURL.endsWith(`/v1/pvp/rooms/${code}/ws`));
        check("route: the ticket is not an access token", (await api.request("GET", "/v1/pvp/profile", undefined, created.body.ticket)).status === 401);

        server.env.PVP_RANDOM = () => 0.15;
        const first = await api.request("POST", "/v1/pvp/rooms", { kind: "room", mediaType: "movie" }, host);
        const draws = [...Array(6).fill(0.15), ...Array(6).fill(0.25)];
        server.env.PVP_RANDOM = () => draws.shift() ?? 0.35;
        const second = await api.request("POST", "/v1/pvp/rooms", { kind: "duel", mediaType: "movie" }, host);
        delete server.env.PVP_RANDOM;
        check("route: a taken code is drawn again", first.body.code === "111111" && second.status === 201 && second.body.code === "222222"
            && second.body.socketURL.endsWith("/v1/pvp/rooms/222222/ws"));

        const missing = await api.request("POST", "/v1/pvp/rooms/999999/ticket", undefined, guest);
        check("route: an unknown room is 404", missing.status === 404 && missing.body.error === "room_not_found");
        const odd = await api.request("POST", "/v1/pvp/rooms/abc/ticket", undefined, guest);
        check("route: a malformed code is 404 without touching an object", odd.status === 404 && !namespace.objects.has("abc"));

        const roomWakes = namespace.object(code).requests;
        const noToken = await api.socket(code, "", 0);
        check("socket: no token is refused", noToken.error === "token_invalid");
        const forged = await api.socket(code, created.body.ticket.replace(/.$/, (c) => (c === "A" ? "B" : "A")), 0);
        check("socket: a forged ticket is refused", forged.error === "token_invalid");
        const junk = await api.socket(code, `pvpr1.${"x".repeat(40)}.yyy`, 0);
        check("socket: a made-up resume token is refused", junk.error === "token_invalid");
        check("socket: none of them woke the room", namespace.object(code).requests === roomWakes);

        const messages = { host: [], guest: [] };
        const hostSocket = await api.socket(code, created.body.ticket, -1);
        hostSocket.onmessage = (text) => messages.host.push(JSON.parse(text));
        const again = await api.socket(code, created.body.ticket, -1);
        check("socket: a ticket opens one socket only", again.error === "ticket_used");
        await namespace.settle();
        check("socket: welcome with the room", messages.host[0]?.t === "welcome" && messages.host[0].snapshot.players[0].name === "NoirGaffer");

        const ticket = await api.request("POST", `/v1/pvp/rooms/${code}/ticket`, undefined, guest);
        const guestSocket = await api.socket(code, ticket.body.ticket, -1);
        guestSocket.onmessage = (text) => messages.guest.push(JSON.parse(text));
        await namespace.settle();
        check("socket: the host sees the guest arrive", messages.host.some((m) => m.t === "player" && m.player.uid !== messages.host[0].you.uid));

        hostSocket.send('{"t":"ping"}');
        const object = namespace.object(code);
        const wakes = object.requests + object.messages;
        check("socket: ping answered without waking the room", messages.host.at(-1).t === "pong" && object.requests + object.messages === wakes);

        hostSocket.send({ t: "start" });
        await namespace.settle();
        const prepare = messages.guest.find((m) => m.t === "prepare");
        check("room object: start loads films from D1 and prepares", prepare && prepare.frames.length === 6 && prepare.total === 5);
        const state = object.instance.state;
        check("room object: only movies, never today's daily", state.match.films.every((film) => film.mediaType === "movie" && film.mediaKey !== "movie_70000"));
        check("room object: five different films", new Set(state.match.films.map((film) => film.mediaKey)).size === 5);
        check("room object: no title went out before its reveal", ![...messages.host, ...messages.guest].some((m) => JSON.stringify(m).includes("Bot Film")));

        // Thrown out of memory between two events: everything comes back from storage.
        object.hibernate();
        hostSocket.send({ t: "ready", film: 1 });
        guestSocket.send({ t: "ready", film: 1 });
        await namespace.settle();
        check("room object: survives hibernation mid-match", messages.guest.some((m) => m.t === "countdown"));
        check("room object: the alarm is set for the film", object.storage.alarm === object.instance.state.match.film.deadline);

        // The guest's socket dies without a close.
        guestSocket.vanish();
        clock.time += 31 * SEC;
        hostSocket.send('{"t":"ping"}');
        await namespace.fireAlarms();
        clock.time += 1 * SEC;
        hostSocket.send({ t: "away", away: false });
        hostSocket.send({ t: "away", away: true });
        await namespace.settle();
        const guestUid = messages.guest[0].you.uid;
        check("room object: a silent socket is noticed as offline", object.instance.state.players[guestUid].connection === "offline");
        check("room object: absent from its last sign of life, not from when it was noticed",
            object.instance.state.players[guestUid].absentSince <= clock.now() - 31 * SEC);

        const resumed = await api.socket(code, messages.guest[0].you.resumeToken, 0);
        const back = [];
        resumed.onmessage = (text) => back.push(JSON.parse(text));
        await namespace.settle();
        check("room object: resume by token, with a snapshot", back[0]?.t === "welcome" && back[0].snapshot.code === code);

        // The poll fallback through the worker.
        const pollResponse = await server.worker.fetch(new Request(`https://api.test/v1/pvp/rooms/${code}/poll`, {
            method: "POST",
            headers: { Authorization: `PvP ${messages.guest[0].you.resumeToken}`, "Content-Type": "application/json" },
            body: JSON.stringify({ lastSeq: 0, send: [] })
        }), server.env, { waitUntil() {} });
        const polled = await pollResponse.json();
        check("poll: works through the worker with the resume token in a header", pollResponse.status === 200 && polled.messages.at(-1).t === "snapshot");
        const pollBad = await server.worker.fetch(new Request(`https://api.test/v1/pvp/rooms/${code}/poll`, {
            method: "POST", headers: { Authorization: "PvP nope" }, body: "{}"
        }), server.env, { waitUntil() {} });
        check("poll: a wrong token is 401 from the worker", pollBad.status === 401 && (await pollBad.json()).error === "token_invalid");
        const otherRoom = await server.worker.fetch(new Request("https://api.test/v1/pvp/rooms/424242/poll", {
            method: "POST", headers: { Authorization: `PvP ${messages.guest[0].you.resumeToken}` }, body: "{}"
        }), server.env, { waitUntil() {} });
        check("poll: a resume token is good for its own room only", otherRoom.status === 401 && !namespace.objects.has("424242"));
        check("resume token: signed, not guessable", messages.guest[0].you.resumeToken.startsWith("pvpr1."));

        // Past the limiter the room is never woken.
        const limited = [];
        server.env.REQUEST_LIMITER = { limit: async ({ key }) => {
            limited.push(key);
            return { success: !key.startsWith("REQUEST_LIMITER:pvp:") };
        } };
        const wokenBefore = object.requests;
        const stopped = await server.worker.fetch(new Request(`https://api.test/v1/pvp/rooms/${code}/poll`, {
            method: "POST", headers: { Authorization: `PvP ${messages.guest[0].you.resumeToken}` }, body: "{}"
        }), server.env, { waitUntil() {} });
        check("limits: a poll or socket storm stops in the worker, keyed by room and player", stopped.status === 429
            && object.requests === wokenBefore && limited.at(-1) === `REQUEST_LIMITER:pvp:${code}:${guestUid}`);
        delete server.env.REQUEST_LIMITER;

        // A client stuck in a loop: the bucket closes its socket, three times
        // and it is out.
        const spammerTicket = await api.request("POST", `/v1/pvp/rooms/${code}/ticket`, undefined, await signIn("spammer"));
        let spammer = await api.socket(code, spammerTicket.body.ticket, -1);
        let spamToken = null;
        let closedWith = null;
        const listen = (socket) => {
            socket.onmessage = (text) => {
                const msg = JSON.parse(text);
                if (msg.t === "welcome") spamToken = msg.you.resumeToken;
            };
            socket.onclose = ({ code: closeCode }) => {
                closedWith = closeCode;
            };
        };
        listen(spammer);
        await namespace.settle();
        const wakesBefore = object.messages;
        for (let i = 0; i < 40; i += 1) spammer.send({ t: "away", away: i % 2 === 0 });
        await namespace.settle();
        check("flood: 30 messages at once pass, the 31st closes the socket", closedWith === 4029
            && object.instance.state.players[Object.keys(object.instance.state.players).at(-1)].floods === 1, `closed ${closedWith}, ${object.messages - wakesBefore} sent`);
        clock.time += 60 * SEC;
        spammer = await api.socket(code, spamToken, -1);
        listen(spammer);
        await namespace.settle();
        closedWith = null;
        for (let i = 0; i < 20; i += 1) {
            spammer.send({ t: "away", away: i % 2 === 0 });
            clock.time += 2 * SEC;
        }
        await namespace.settle();
        check("flood: one message every 2 s goes on forever", closedWith === null);
        spammer.send("x".repeat(5000));
        await namespace.settle();
        check("flood: an oversized message counts as flooding", closedWith === 4029);
        spammer = await api.socket(code, spamToken, -1);
        listen(spammer);
        await namespace.settle();
        for (let i = 0; i < 40; i += 1) spammer.send({ t: "away", away: i % 2 === 0 });
        await namespace.settle();
        const refused = await api.socket(code, spamToken, -1);
        check("flood: the third time the socket closes for good and the token stops working", closedWith === 4030 && refused.error === "resume_invalid");

        // Leave everything to the alarm: the room cleans itself up.
        hostSocket.close();
        resumed.close();
        await namespace.settle();
        for (let i = 0; i < 40 && object.instance.state; i += 1) {
            clock.time = Math.max(clock.time + SEC, namespace.nextAlarm() ?? clock.time);
            await namespace.fireAlarms();
        }
        check("room object: an abandoned room deletes itself and frees the code", object.instance.state === null && object.storage.values.size === 0);
        const gone = await api.request("POST", `/v1/pvp/rooms/${code}/ticket`, undefined, guest);
        check("route: a cleaned-up room is 404", gone.status === 404);

        db.exec("UPDATE users SET role = 'admin'");
        await api.request("PATCH", "/v1/admin/config", { pvpEnabled: false }, host);
        const disabled = await api.request("POST", "/v1/pvp/rooms", { kind: "room", mediaType: "movie" }, host);
        check("route: the switch in app_config turns PvP off", disabled.status === 503 && disabled.body.error === "pvp_disabled");

        // The key query rides the shuffle index like a round pick does.
        const { buildCatalogQuery } = await import(`${API}src/lib/media.js`);
        const { where, bindings } = buildCatalogQuery({ mediaType: "movie", minApprovedImages: 6, query: null, yearFrom: null, yearTo: null, languages: [], genres: [] }, { excludeDailyFrom: today });
        const plan = db.plan(`SELECT m.key FROM media_items m INDEXED BY idx_media_shuffle WHERE ${where} AND m.shuffle_key >= ? ORDER BY m.shuffle_key LIMIT ?`, [...bindings, 0.5, 20]).join(" | ");
        check("films: the key query uses the shuffle index, no sort", plan.includes("idx_media_shuffle") && !/TEMP B-TREE/.test(plan), `\n      ${plan}`);
    }
    {
        const server = await localServer({ films: 4 });
        const films = await loadMatchFilms(server.env, { mediaType: "movie", frames: 6, count: 10, seedText: "X:1", now: server.clock.now() });
        check("films: a small pool shortens the match instead of failing", films.length === 4);
        const again = await loadMatchFilms(server.env, { mediaType: "movie", frames: 6, count: 10, seedText: "X:1", now: server.clock.now() });
        check("films: the same seed lays out the same match", JSON.stringify(again) === JSON.stringify(films));
        const fewFrames = await loadMatchFilms(server.env, { mediaType: "movie", frames: 6, count: 10, seedText: "X:2", now: server.clock.now() });
        check("films: each one has 6 frames and spares", fewFrames.every((film) => film.frames.length === 6 && film.spares.length === 3));
        check("films: seed SQL has no compound inserts", seedStatements(2).every((sql) => !/UNION/i.test(sql)));
    }

    // -------------------------------------------------------------- bots, whole matches
    for (const [label, options] of [
        ["bots: a room of four plays five films", { kind: "room", players: 4, films: 5 }],
        ["bots: a room of eight with a dropout", { kind: "room", players: 8, films: 5, drop: true }],
        ["bots: a duel to a knockout with a dropout", { kind: "duel", drop: true, accuracy: 0.6 }],
        ["bots: a duel of weak players", { kind: "duel", accuracy: 0.1 }]
    ]) {
        const server = await localServer();
        const bots = await playMatch({ ...options, api: server.api, loop: server.loop, oracle: server.oracle, random: seededRandom(7) });
        const finished = bots[0].finished;
        const sameEnd = bots.every((bot) => bot.finished && JSON.stringify(bot.finished.standings) === JSON.stringify(finished.standings));
        const object = [...server.namespace.objects.values()][0];
        const ok = finished && sameEnd && bots.every((bot) => !bot.errors.length)
            && (options.kind === "room" ? finished.films.length === 5 : ["knockout", "films_done", "draw"].includes(finished.reason));
        check(`${label} (${finished?.reason}, ${finished?.films.length} films, ${object.messages} msgs, ${object.alarms} alarms, ${object.storage.writes} writes)`, ok,
            JSON.stringify({ reason: finished?.reason, errors: bots.map((bot) => bot.errors) }));
    }
}
