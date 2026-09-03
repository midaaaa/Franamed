// Shared shapes and queries for the curated catalogue.

import { badRequest, parseInteger } from "./http.js";

export const MEDIA_TYPES = ["movie", "tv"];
export const IMAGE_STATUSES = ["pending", "approved", "rejected"];
export const DIFFICULTY_TIERS = ["hard", "medium", "easy"];
export const REPORT_REASONS = ["poster", "not_a_frame", "bad_quality", "unclear"];

export function mediaKey(mediaType, tmdbId) {
    if (!MEDIA_TYPES.includes(mediaType)) throw badRequest(`Unknown media type "${mediaType}"`);
    return `${mediaType}_${tmdbId}`;
}

export function serializeMediaItem(row, genreIds = []) {
    return {
        key: row.key,
        tmdbId: row.tmdb_id,
        mediaType: row.media_type,
        title: row.title,
        originalTitle: row.original_title,
        releaseYear: row.release_year,
        originalLanguage: row.original_language,
        popularity: row.popularity,
        posterURL: row.poster_url,
        status: row.status,
        genreIds,
        totalImages: row.total_images,
        reviewedImages: row.reviewed_images,
        approvedImages: row.approved_images,
        adminFinalized: row.admin_finalized === 1,
        finalizedAt: row.finalized_at,
        lastSyncedAt: row.last_synced_at
    };
}

export function serializeImage(row) {
    return {
        id: row.id,
        mediaKey: row.media_key,
        filePath: row.file_path,
        status: row.status,
        reportWeight: row.report_weight,
        perceptualHash: row.perceptual_hash,
        clusteredWith: row.clustered_with,
        difficultyTier: row.difficulty_tier,
        difficultyRank: row.difficulty_rank,
        moderatorStatus: row.moderator_status ?? null,
        moderatorAt: row.moderator_at ?? null,
        disputesDismissedCount: row.disputes_dismissed_count ?? 0,
        voteAverage: row.tmdb_vote_average,
        voteCount: row.tmdb_vote_count,
        width: row.width,
        height: row.height,
        aspectRatio: row.aspect_ratio
    };
}

// Reads the filter set out of a query string.
//
// Rating filters are intentionally absent. Ratings drift constantly on TMDB, so
// a copy kept here would answer with numbers that quietly go stale; the curated
// pool therefore filters on genre, year and language only. The fully random
// TMDB pool still supports rating filters, because there the numbers come
// straight from TMDB at request time.
export function parseFilters(url) {
    const params = url.searchParams;

    const mediaType = params.get("mediaType") || "movie";
    if (!MEDIA_TYPES.includes(mediaType)) throw badRequest(`Unknown media type "${mediaType}"`);

    const genres = (params.get("genres") || "")
        .split(",")
        .map((value) => Number.parseInt(value, 10))
        .filter((value) => Number.isInteger(value));

    const languages = (params.get("languages") || "")
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean);

    const query = (params.get("q") || "").trim().slice(0, 100);

    return {
        mediaType,
        genres,
        languages,
        query,
        yearFrom: parseInteger(params.get("yearFrom"), { min: 1874, max: 2200 }),
        yearTo: parseInteger(params.get("yearTo"), { min: 1874, max: 2200 }),
        minApprovedImages: parseInteger(params.get("minApprovedImages"), { fallback: 6, min: 1, max: 50 })
    };
}

// Builds the WHERE clause shared by "pick a round", "count the pool" and
// "browse the catalogue", so those three can never drift apart.
// `includeUnapproved` is the moderator's view of the catalogue: a title that is
// not playable yet is exactly the one they need to find and work on, so the
// playable-pool conditions have to come off for them.
export function buildCatalogQuery(
    filters,
    { uid = null, excludeWatched = false, playlistId = null, includeUnapproved = false } = {}
) {
    const conditions = ["m.media_type = ?"];
    const bindings = [filters.mediaType];

    if (!includeUnapproved) {
        conditions.push("m.status = 'approved'", "m.approved_images >= ?");
        bindings.push(filters.minApprovedImages);
    }

    if (filters.query) {
        // Matches the localised and the original title, since a moderator may
        // remember either one.
        conditions.push("(m.title LIKE ? OR m.original_title LIKE ?)");
        bindings.push(`%${filters.query}%`, `%${filters.query}%`);
    }

    if (filters.yearFrom !== null) {
        conditions.push("m.release_year >= ?");
        bindings.push(filters.yearFrom);
    }
    if (filters.yearTo !== null) {
        conditions.push("m.release_year <= ?");
        bindings.push(filters.yearTo);
    }
    if (filters.languages.length) {
        conditions.push(`m.original_language IN (${filters.languages.map(() => "?").join(", ")})`);
        bindings.push(...filters.languages);
    }
    if (filters.genres.length) {
        // "Any of these genres", matching how TMDB's discover endpoint treats a
        // pipe-separated genre list.
        conditions.push(
            `EXISTS (SELECT 1 FROM media_genres g WHERE g.media_key = m.key AND g.genre_id IN (${filters.genres
                .map(() => "?")
                .join(", ")}))`
        );
        bindings.push(...filters.genres);
    }
    if (playlistId) {
        conditions.push("EXISTS (SELECT 1 FROM playlist_items p WHERE p.media_key = m.key AND p.playlist_id = ?)");
        bindings.push(playlistId);
    }
    if (excludeWatched && uid) {
        conditions.push("NOT EXISTS (SELECT 1 FROM watched_media w WHERE w.media_key = m.key AND w.uid = ?)");
        bindings.push(uid);
    }

    return { where: conditions.join(" AND "), bindings };
}

export async function loadGenreIds(env, mediaKeys) {
    if (!mediaKeys.length) return new Map();

    const rows = await env.DB.prepare(
        `SELECT media_key, genre_id FROM media_genres WHERE media_key IN (${mediaKeys.map(() => "?").join(", ")})`
    ).bind(...mediaKeys).all();

    const byKey = new Map(mediaKeys.map((key) => [key, []]));
    for (const row of rows.results) byKey.get(row.media_key)?.push(row.genre_id);
    return byKey;
}

// Recomputes the cached counters on a media item. They are derived rather than
// hand-set so they cannot drift away from the image rows underneath.
export async function refreshMediaCounters(env, key) {
    const counts = await env.DB.prepare(
        `SELECT COUNT(*) AS total,
                SUM(CASE WHEN status != 'pending' THEN 1 ELSE 0 END) AS reviewed,
                SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) AS approved
         FROM media_images WHERE media_key = ?`
    ).bind(key).first();

    const approved = counts.approved || 0;

    // A title becomes playable the moment it has an approved image; admin
    // finalisation is queue housekeeping and deliberately not a gameplay gate.
    await env.DB.prepare(
        `UPDATE media_items
         SET total_images = ?, reviewed_images = ?, approved_images = ?,
             status = CASE WHEN ? > 0 THEN 'approved' ELSE status END
         WHERE key = ?`
    ).bind(counts.total || 0, counts.reviewed || 0, approved, approved, key).run();
}
