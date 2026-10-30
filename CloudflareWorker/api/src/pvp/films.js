// The films of one match, picked once when it starts and frozen into the room.
//
// Only the catalogue is read: a match never looks at what its players have
// played elsewhere. What it does avoid is repeating itself: a room remembers
// what it dealt, takes fresh titles first, and when the pool runs short tops up
// from the older half of what it played, the way a shuffled playlist rests its
// recent entries.

import { buildCatalogQuery } from "../lib/media.js";
import { seededRandom, selectRoundFrames, selectSpareFrames } from "../lib/frames.js";
import { hashString, utcDateString } from "../lib/daily.js";

const SPARE_FRAME_COUNT = 3;
const KEY_SAMPLE_LIMIT = 90;
// Titles beyond `count` kept in reserve for ones whose frames fall short.
const RESERVE = 5;

function shuffled(items, random) {
    const copy = [...items];
    for (let i = copy.length - 1; i > 0; i -= 1) {
        const j = Math.floor(random() * (i + 1));
        [copy[i], copy[j]] = [copy[j], copy[i]];
    }
    return copy;
}

// Fresh first; then the older half of the played, then the rest.
export function chooseKeys(keys, played, count, random) {
    const fresh = shuffled(keys.filter((key) => !(key in played)), random);
    const replay = keys.filter((key) => key in played).sort((a, b) => played[a] - played[b] || (a < b ? -1 : 1));
    const half = Math.ceil(replay.length / 2);
    return [...fresh, ...shuffled(replay.slice(0, half), random), ...shuffled(replay.slice(half), random)].slice(0, count);
}

export async function loadMatchFilms(env, { mediaType, frames, count, played = {}, seedText, now = Date.now() }) {
    const random = seededRandom(hashString(seedText));
    const filters = { mediaType, minApprovedImages: frames, query: null, yearFrom: null, yearTo: null, languages: [], genres: [] };
    const { where, bindings } = buildCatalogQuery(filters, { excludeDailyFrom: utcDateString(new Date(now)) });

    // A window of the shuffled pool from a random point, wrapping round.
    const limit = Math.min(KEY_SAMPLE_LIMIT, 3 * count + Object.keys(played).length);
    const point = random();
    const from = `SELECT m.key FROM media_items m INDEXED BY idx_media_shuffle WHERE ${where}`;
    const keys = (await env.DB.prepare(`${from} AND m.shuffle_key >= ? ORDER BY m.shuffle_key LIMIT ?`)
        .bind(...bindings, point, limit).all()).results.map((row) => row.key);
    if (keys.length < limit) {
        const wrapped = await env.DB.prepare(`${from} AND m.shuffle_key < ? ORDER BY m.shuffle_key LIMIT ?`)
            .bind(...bindings, point, limit - keys.length).all();
        keys.push(...wrapped.results.map((row) => row.key));
    }

    const chosen = chooseKeys(keys, played, count + RESERVE, random);
    if (!chosen.length) return [];

    const marks = chosen.map(() => "?").join(", ");
    const items = (await env.DB.prepare(
        `SELECT key, tmdb_id, media_type, title, original_title, release_year, poster_url FROM media_items WHERE key IN (${marks})`
    ).bind(...chosen).all()).results;
    const images = (await env.DB.prepare(
        `SELECT * FROM media_images WHERE media_key IN (${marks}) AND status = 'approved' AND missing_at IS NULL`
    ).bind(...chosen).all()).results;

    const itemByKey = new Map(items.map((item) => [item.key, item]));
    const imagesByKey = new Map();
    for (const image of images) {
        if (!imagesByKey.has(image.media_key)) imagesByKey.set(image.media_key, []);
        imagesByKey.get(image.media_key).push(image);
    }

    const films = [];
    for (const key of chosen) {
        if (films.length >= count) break;
        const item = itemByKey.get(key);
        const pool = imagesByKey.get(key) || [];
        const layout = selectRoundFrames(pool, frames, { random });
        if (!item || layout.length < frames) continue;
        const spares = selectSpareFrames(pool, new Set(layout.map((image) => image.id)), SPARE_FRAME_COUNT, { random });
        films.push({
            mediaKey: key,
            tmdbId: item.tmdb_id,
            mediaType: item.media_type,
            title: item.title,
            originalTitle: item.original_title,
            year: item.release_year,
            posterPath: item.poster_url,
            frames: layout.map(frameOf),
            spares: spares.map(frameOf)
        });
    }
    return films;
}

function frameOf(image) {
    return { path: image.file_path, width: image.width ?? null, height: image.height ?? null };
}
