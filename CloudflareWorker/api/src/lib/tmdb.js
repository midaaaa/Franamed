// Pulls titles into the catalogue from TMDB.
//
// The Worker talks to TMDB directly rather than through the image proxy: the
// proxy exists because TMDB is unreachable from Russian networks, and a Worker
// is not on one.

import { APIError } from "./http.js";
import { mediaKey } from "./media.js";

const TMDB_ORIGIN = "https://api.themoviedb.org/3";

async function tmdbFetch(env, path, params = {}) {
    if (!env.TMDB_API_KEY) throw new APIError(500, "server_misconfigured", "TMDB_API_KEY is not set");

    const url = new URL(`${TMDB_ORIGIN}${path}`);
    url.searchParams.set("api_key", env.TMDB_API_KEY);
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);

    const response = await fetch(url.toString());
    if (!response.ok) {
        throw new APIError(502, "tmdb_error", `TMDB responded with ${response.status}`);
    }
    return response.json();
}

function releaseYear(details, mediaType) {
    const date = mediaType === "movie" ? details.release_date : details.first_air_date;
    if (!date) return null;
    const year = Number.parseInt(date.slice(0, 4), 10);
    return Number.isInteger(year) ? year : null;
}

export async function fetchDiscoverPage(env, mediaType, { page = 1, language = "ru-RU", sortBy = "popularity.desc" } = {}) {
    return tmdbFetch(env, `/discover/${mediaType}`, { page: String(page), language, sort_by: sortBy });
}

// Fetches one title with its images in a single call and writes it into the
// catalogue. Images arrive as `pending` — nothing is playable until a curator
// or the community approves it.
export async function importMediaItem(env, mediaType, tmdbId, { addedBy = null, language = "ru-RU" } = {}) {
    const details = await tmdbFetch(env, `/${mediaType}/${tmdbId}`, {
        language,
        append_to_response: "images",
        // Asking for no image language returns the language-neutral stills,
        // which are the ones without burned-in titles or credits.
        include_image_language: "null"
    });

    const key = mediaKey(mediaType, tmdbId);
    const now = Date.now();

    await env.DB.prepare(
        `INSERT INTO media_items (key, tmdb_id, media_type, title, original_title, release_year,
                                  original_language, popularity, added_by, last_synced_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (key) DO UPDATE SET
            title = excluded.title,
            original_title = excluded.original_title,
            release_year = excluded.release_year,
            original_language = excluded.original_language,
            popularity = excluded.popularity,
            last_synced_at = excluded.last_synced_at`
    ).bind(
        key,
        tmdbId,
        mediaType,
        mediaType === "movie" ? details.title : details.name,
        mediaType === "movie" ? details.original_title : details.original_name,
        releaseYear(details, mediaType),
        details.original_language || null,
        details.popularity || 0,
        addedBy,
        now,
        now
    ).run();

    const statements = [];

    for (const genre of details.genres || []) {
        statements.push(
            env.DB.prepare("INSERT OR IGNORE INTO media_genres (media_key, genre_id) VALUES (?, ?)").bind(key, genre.id)
        );
    }

    const backdrops = (details.images?.backdrops || []).filter((image) => image.iso_639_1 === null);

    for (const backdrop of backdrops) {
        // Existing rows keep their curation state: re-syncing a title must
        // never silently reset votes a curator already cast.
        statements.push(
            env.DB.prepare(
                `INSERT INTO media_images (media_key, file_path, tmdb_vote_average, tmdb_vote_count,
                                           width, height, aspect_ratio, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT (media_key, file_path) DO UPDATE SET
                    tmdb_vote_average = excluded.tmdb_vote_average,
                    tmdb_vote_count = excluded.tmdb_vote_count`
            ).bind(
                key,
                backdrop.file_path,
                backdrop.vote_average || 0,
                backdrop.vote_count || 0,
                backdrop.width || null,
                backdrop.height || null,
                backdrop.aspect_ratio || null,
                now
            )
        );
    }

    if (statements.length) await env.DB.batch(statements);

    return { key, importedImages: backdrops.length, posterPath: details.poster_path || null };
}

export async function fetchPosterOptions(env, mediaType, tmdbId) {
    const body = await tmdbFetch(env, `/${mediaType}/${tmdbId}/images`, { include_image_language: "ru,en,null" });
    return (body.posters || []).map((poster) => ({
        filePath: poster.file_path,
        language: poster.iso_639_1,
        voteAverage: poster.vote_average,
        width: poster.width,
        height: poster.height
    }));
}
