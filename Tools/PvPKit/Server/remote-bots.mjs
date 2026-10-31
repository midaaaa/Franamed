// Bots that join an existing room on a running worker (wrangler dev) and play
// it out, for the Swift client to play against.
//
//   node --no-warnings Tools/PvPKit/Server/remote-bots.mjs --url http://127.0.0.1:8787 --code ABCDEF [--count 2] [--ready] [--db <sqlite>]
//
// Prints {"uid": …} per bot once it is in the room, then {"finished": reason}.

import { readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

const API = new URL("../../../CloudflareWorker/api/", import.meta.url).pathname;
const { Bot, RemoteApi, RealLoop, oracleFrom } = await import(`${API}tools/pvp-bots.mjs`);
const { seededRandom } = await import(`${API}src/lib/frames.js`);

function option(name, fallback) {
    const index = process.argv.indexOf(`--${name}`);
    return index === -1 ? fallback : process.argv[index + 1];
}

function wranglerDatabase() {
    const dir = join(API, ".wrangler/state/v3/d1/miniflare-D1DatabaseObject");
    if (!existsSync(dir)) return null;
    const file = readdirSync(dir).find((name) => name.endsWith(".sqlite"));
    return file ? join(dir, file) : null;
}

const db = new DatabaseSync(option("db", null) || wranglerDatabase(), { readOnly: true });
const oracle = oracleFrom((path) => db.prepare(
    "SELECT m.tmdb_id AS tmdbId, m.media_type AS mediaType FROM media_images i JOIN media_items m ON m.key = i.media_key WHERE i.file_path = ?"
).get(path));

const api = new RemoteApi(option("url", "http://127.0.0.1:8787"));
const loop = new RealLoop();
const random = seededRandom(Number(option("seed", 11)));
const names = ["NeonUsher", "RetroSlate", "CultEditor"];
const bots = names.slice(0, Number(option("count", 1))).map((name) => new Bot({ name, api, loop, oracle, random, accuracy: Number(option("accuracy", 0.7)), think: [500, 2000] }));

for (const bot of bots) {
    await bot.signIn();
    await bot.join(option("code"));
    if (process.argv.includes("--ready")) loop.after(300, () => bot.send({ t: "ready", film: 0 }));
    console.log(JSON.stringify({ uid: bot.uid }));
}
await loop.run({ until: () => bots.every((bot) => bot.finished || bot.closedWith), limitMs: 10 * 60 * 1000 });
console.log(JSON.stringify({ finished: bots[0].finished?.reason ?? null }));
process.exit(0);
