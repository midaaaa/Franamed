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
        lastSyncedAt: row.last_synced_at,
        rejectedAt: row.rejected_at ?? null,
        rejectedReason: row.rejected_reason ?? null,
        previewPath: row.preview_path ?? null,
        pendingImages: row.pending_images ?? 0,
        unjudgedImages: row.unjudged_images ?? 0,
        untieredApproved: row.untiered_approved ?? 0
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

// The curator's views of the catalogue, answered from the counters that
// `refreshMediaCounters` keeps on the title row: no filter looks at frames.
export const CURATION_FILTERS = {
    needsWork: "m.work_weight > 0",
    // Has something, but not the six a round needs.
    almostPlayable: "m.approved_images BETWEEN 1 AND 5",
    untouched: "m.reviewed_images = 0 AND m.total_images > 0",
    // Untagged frames play, but only as filler: they cannot fill a difficulty slot.
    noTiers: "m.untiered_approved > 0",
    // Re-importing only adds rows, so an unjudged frame on a worked title is
    // one TMDB added since.
    hasNewFrames: "m.unjudged_images > 0 AND m.unjudged_images < m.total_images",
    noPoster: "m.poster_url IS NULL",
    rejected: "m.status = 'rejected'"
};

export const CURATION_FILTER_NAMES = Object.keys(CURATION_FILTERS);

// Every order ends on the key: OFFSET paging over ties is otherwise free to
// repeat or skip a title between pages.
export function catalogOrderBy(sort) {
    switch (sort) {
        case "needsWork":
            return { sql: "m.work_weight DESC, m.key", bindings: [] };
        case "title":
            return { sql: "m.title COLLATE NOCASE ASC, m.key", bindings: [] };
        case "recent":
            return { sql: "m.created_at DESC, m.key", bindings: [] };
        case "popularity":
        default:
            return { sql: "m.popularity DESC, m.key", bindings: [] };
    }
}

// Builds the WHERE clause shared by "pick a round", "count the pool" and
// "browse the catalogue", so those three can never drift apart.
// `includeUnapproved` is the moderator's view of the catalogue: a title that is
// not playable yet is exactly the one they need to find and work on, so the
// playable-pool conditions have to come off for them.
export function buildCatalogQuery(
    filters,
    {
        uid = null,
        excludeWatched = false,
        playlistId = null,
        includeUnapproved = false,
        curationFilter = null,
        includeRejected = false,
        target = null
    } = {}
) {
    const conditions = ["m.media_type = ?"];
    const bindings = [filters.mediaType];

    if (!includeUnapproved) {
        conditions.push("m.status = 'approved'", "m.approved_images >= ?");
        bindings.push(filters.minApprovedImages);
    }

    // Otherwise "rejected" would mean nothing more than "hidden from players".
    if (includeUnapproved && !includeRejected && curationFilter !== "rejected") {
        conditions.push("m.status != 'rejected'");
    }

    if (curationFilter) {
        const clause = CURATION_FILTERS[curationFilter];
        if (!clause) throw badRequest(`Unknown curation filter "${curationFilter}"`);
        if (clause.includes("?target") && !Number.isInteger(target)) {
            throw badRequest(`The "${curationFilter}" filter needs a curation target`);
        }

        if (clause.includes("?target")) {
            conditions.push(clause.replaceAll("?target", "?"));
            for (let i = 0; i < clause.split("?target").length - 1; i += 1) bindings.push(target);
        } else {
            conditions.push(clause);
        }
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

// Where an hour of curating buys most. Zero means "not in the queue at all", so
// the queue is a range scan on idx_media_work rather than a filtered sort.
export function workWeight({ status, adminFinalized, popularity, total, reviewed, approved }, target) {
    if (status === "rejected" || adminFinalized || total === 0 || reviewed >= total || approved >= target) return 0;
    return popularity * ((target - approved) / target) + 0.01;
}

export async function readTarget(env) {
    const row = await env.DB.prepare("SELECT value FROM app_config WHERE key = 'targetApprovedFrames'").first();
    const target = Number.parseInt(row?.value ?? "", 10);
    return Number.isInteger(target) && target > 0 ? target : 12;
}

// The same rule as `workWeight`, for every title at once: the target only
// changes from the admin config, and then every weight moves with it.
export async function recomputeWorkWeights(env, target) {
    await env.DB.prepare(
        `UPDATE media_items SET work_weight = CASE
             WHEN status = 'rejected' OR admin_finalized = 1 OR total_images = 0
                  OR reviewed_images >= total_images OR approved_images >= ?1 THEN 0
             ELSE popularity * (CAST(?1 - approved_images AS REAL) / ?1) + 0.01
         END`
    ).bind(target).run();
}

// Recomputes everything a list screen reads off a title. Derived rather than
// hand-set so it cannot drift from the frames underneath, and read in one pass
// over this title's frames — writes are rare, list reads are not.
export async function refreshMediaCounters(env, key, { target } = {}) {
    const item = await env.DB.prepare(
        "SELECT status, admin_finalized, popularity, work_weight FROM media_items WHERE key = ?"
    ).bind(key).first();
    if (!item) return;

    const frames = await env.DB.prepare(
        `SELECT id, status, moderator_status, difficulty_tier, file_path, tmdb_vote_average
         FROM media_images WHERE media_key = ?`
    ).bind(key).all();

    const counts = { total: 0, reviewed: 0, approved: 0, pending: 0, unjudged: 0, untiered: 0 };
    let preview = null;
    const standing = { approved: 0, pending: 1, rejected: 2 };

    for (const frame of frames.results) {
        counts.total += 1;
        if (frame.status !== "pending") counts.reviewed += 1;
        if (frame.status === "pending") counts.pending += 1;
        if (frame.status === "approved") counts.approved += 1;
        if (frame.status === "approved" && frame.difficulty_tier === null) counts.untiered += 1;
        if (frame.moderator_status === null) counts.unjudged += 1;

        const better = !preview
            || standing[frame.status] < standing[preview.status]
            || (standing[frame.status] === standing[preview.status]
                && (frame.tmdb_vote_average > preview.tmdb_vote_average
                    || (frame.tmdb_vote_average === preview.tmdb_vote_average && frame.id < preview.id)));
        if (better) preview = frame;
    }

    // A title becomes playable the moment it has an approved image; admin
    // finalisation is queue housekeeping and deliberately not a gameplay gate.
    // 'rejected' is sticky: undoing it is `/catalog/items/{key}/reset`, never a
    // side effect of a lock on some frame.
    const status = item.status === "rejected" ? "rejected" : counts.approved > 0 ? "approved" : item.status;
    const weight = workWeight({
        status,
        adminFinalized: item.admin_finalized === 1,
        popularity: item.popularity,
        total: counts.total,
        reviewed: counts.reviewed,
        approved: counts.approved
    }, target ?? await readTarget(env));

    // Status and weight sit in several indexes, and D1 bills a written row per
    // index touched, so they are only set when they actually move.
    const moved = [];
    const movedValues = [];
    if (status !== item.status) {
        moved.push("status = ?");
        movedValues.push(status);
    }
    if (weight !== item.work_weight) {
        moved.push("work_weight = ?");
        movedValues.push(weight);
    }

    await env.DB.prepare(
        `UPDATE media_items
         SET total_images = ?, reviewed_images = ?, approved_images = ?,
             pending_images = ?, unjudged_images = ?, untiered_approved = ?,
             preview_path = ?${moved.map((clause) => `, ${clause}`).join("")}
         WHERE key = ?`
    ).bind(
        counts.total, counts.reviewed, counts.approved,
        counts.pending, counts.unjudged, counts.untiered,
        preview?.file_path ?? null, ...movedValues, key
    ).run();
}

// Every frame's status on one title, re-derived from the live reports in a
// single statement: a title can carry 170 frames and D1 allows 50
// queries per invocation, so the per-frame path cannot be looped.
export async function recomputeTitleImageStatuses(env, key, { autoHideReportWeight }) {
    const liveReportWeight = `(SELECT COALESCE(SUM(r.weight), 0) FROM image_reports r
                                WHERE r.image_id = media_images.id AND r.dismissed_at IS NULL)`;

    await env.DB.prepare(
        `UPDATE media_images
         SET report_weight = ${liveReportWeight},
             status = CASE
                 WHEN moderator_status IS NOT NULL THEN moderator_status
                 WHEN ${liveReportWeight} >= ?1 THEN 'rejected'
                 ELSE 'pending'
             END
         WHERE media_key = ?2`
    ).bind(autoHideReportWeight, key).run();

    await refreshMediaCounters(env, key);
}
