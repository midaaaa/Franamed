// Plays one match of bots against the in-process worker (virtual clock) and
// prints, as JSON lines, everything the first bot received with the time it
// arrived: {"at": ms from the start, "msg": {...}}. A reconnect is a line
// {"at": …, "reconnect": true}. With --expect each line also carries the
// room's own snapshot for that bot at that moment, to check a client against.
//
//   node --no-warnings Tools/PvPKit/Server/record-traffic.mjs --kind room --players 4 --films 5 --drop 20 --seed 3

const API = new URL("../../../CloudflareWorker/api/", import.meta.url).pathname;
const { Bot, localServer, playMatch } = await import(`${API}tools/pvp-bots.mjs`);
const { seededRandom } = await import(`${API}src/lib/frames.js`);
const { snapshot } = await import(`${API}src/pvp/core.js`);

function option(name, fallback) {
    const index = process.argv.indexOf(`--${name}`);
    return index === -1 ? fallback : process.argv[index + 1];
}

const server = await localServer();
const started = server.clock.now();
const lines = [];
const watched = option("watch", "NoirGaffer");
const expect = process.argv.includes("--expect");

const receive = Bot.prototype.receive;
Bot.prototype.receive = function (msg) {
    if (this.name === watched) {
        const line = { at: server.clock.now() - started, msg };
        const room = server.namespace.objects.get(this.code)?.instance.state;
        if (expect && room?.players[this.uid]) line.expect = snapshot(room, this.uid, server.clock.now());
        lines.push(line);
    }
    return receive.call(this, msg);
};
const connect = Bot.prototype.connect;
Bot.prototype.connect = function (token) {
    if (this.name === watched && this.resumeToken) lines.push({ at: server.clock.now() - started, reconnect: true });
    return connect.call(this, token);
};

const drop = option("drop", null);
const bots = await playMatch({
    api: server.api,
    loop: server.loop,
    oracle: server.oracle,
    random: seededRandom(Number(option("seed", 1))),
    kind: option("kind", "room"),
    players: Number(option("players", 4)),
    films: Number(option("films", 5)),
    time: Number(option("time", 30)),
    accuracy: Number(option("accuracy", 0.5)),
    drop: drop !== null,
    dropMs: Number(drop ?? 20) * 1000
});
if (!bots[0].finished) {
    console.error("match did not finish");
    process.exit(1);
}
// One step of the room reaches a bot as a burst at one moment; only the last
// message of a burst has the whole step behind it.
lines.forEach((line, i) => {
    if (lines[i + 1]?.at === line.at) delete line.expect;
    console.log(JSON.stringify(line));
});
