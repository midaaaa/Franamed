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

// Films and series in one call; people are dropped. TMDB does the matching, so
// case, "ё" and original titles all work, which a LIKE over D1 cannot.
export async function searchTitles(env, query, { language = "ru-RU" } = {}) {
    const body = await tmdbFetch(env, "/search/multi", { query, language, include_adult: "false" });
    return (body.results || [])
        .filter((entry) => entry.media_type === "movie" || entry.media_type === "tv")
        .map((entry) => {
            const date = entry.release_date || entry.first_air_date || "";
            const year = Number.parseInt(date.slice(0, 4), 10);
            return {
                tmdbId: entry.id,
                mediaType: entry.media_type,
                key: mediaKey(entry.media_type, entry.id),
                title: entry.title || entry.name || "",
                originalTitle: entry.original_title || entry.original_name || "",
                year: Number.isInteger(year) ? year : null,
                posterPath: entry.poster_path || null
            };
        });
}

export const SHOWCASE_LISTS = ["known", "popular", "top", "trending"];

function toHit(entry, mediaType) {
    const date = entry.release_date || entry.first_air_date || "";
    const year = Number.parseInt(date.slice(0, 4), 10);
    return {
        tmdbId: entry.id,
        mediaType,
        key: mediaKey(mediaType, entry.id),
        title: entry.title || entry.name || "",
        originalTitle: entry.original_title || entry.original_name || "",
        year: Number.isInteger(year) ? year : null,
        posterPath: entry.poster_path || null
    };
}

// "Known" sorts by vote count: for a guessing game, how many people have seen
// a film matters more than how it rated. Trending has no filters on TMDB.
export async function fetchShowcasePage(env, { list, mediaType, page, decade = null, genre = null, language = "ru-RU" }) {
    let body;
    if (list === "trending") {
        body = await tmdbFetch(env, `/trending/${mediaType}/week`, { page: String(page), language });
    } else {
        const params = {
            page: String(page),
            language,
            include_adult: "false",
            sort_by: { known: "vote_count.desc", popular: "popularity.desc", top: "vote_average.desc" }[list]
        };
        if (list === "top") params["vote_count.gte"] = "1000";
        if (genre) params.with_genres = String(genre);
        if (decade) {
            const field = mediaType === "movie" ? "primary_release_date" : "first_air_date";
            params[`${field}.gte`] = `${decade}-01-01`;
            params[`${field}.lte`] = `${decade + 9}-12-31`;
        }
        body = await tmdbFetch(env, `/discover/${mediaType}`, params);
    }

    return {
        hits: (body.results || []).map((entry) => toHit(entry, mediaType)),
        hasMore: (body.page || page) < Math.min(body.total_pages || 0, 500)
    };
}

export async function fetchDiscoverPage(env, mediaType, { page = 1, language = "ru-RU", sortBy = "popularity.desc" } = {}) {
    return tmdbFetch(env, `/discover/${mediaType}`, { page: String(page), language, sort_by: sortBy });
}

// Fetches one title with its images in a single call and writes it into the
// catalogue. Images arrive as `pending` — nothing is playable until a curator
// or the community approves it.
// The images came back filtered to no language, so these posters carry no
// title lettering; the best rated of them beats TMDB's default, which usually
// does. Falls back to the default when a title has no clean one.
function bestPoster(details) {
    const clean = [...(details.images?.posters || [])].sort(
        (a, b) => (b.vote_average || 0) - (a.vote_average || 0) || (b.vote_count || 0) - (a.vote_count || 0)
    );
    return clean[0]?.file_path || details.poster_path || null;
}

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
                                  original_language, popularity, poster_url, added_by, last_synced_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT (key) DO UPDATE SET
            poster_url = COALESCE(media_items.poster_url, excluded.poster_url),
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
        bestPoster(details),
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
