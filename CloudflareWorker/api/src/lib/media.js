// Shared shapes and queries for the curated catalogue.

import { badRequest, parseInteger } from "./http.js";
import { markIndexDirtyStatement } from "./catalogIndex.js";

export const MEDIA_TYPES = ["movie", "tv"];
export const IMAGE_STATUSES = ["pending", "approved", "rejected"];
export const DIFFICULTY_TIERS = ["hard", "medium", "easy"];
export const REPORT_REASONS = ["poster", "not_a_frame", "bad_quality", "unclear"];
export const PUBLISH_MODES = ["auto", "on", "off"];

// The smallest round, so the fewest approved frames a published title can have.
export const PUBLISH_MIN_FRAMES = 6;

// A workbench left open without a word from its app stops counting as someone
// working after this long.
export const PRESENCE_WINDOW_MS = 2 * 60 * 60 * 1000;

export function mediaKey(mediaType, tmdbId) {
    if (!MEDIA_TYPES.includes(mediaType)) throw badRequest(`Unknown media type "${mediaType}"`);
    return `${mediaType}_${tmdbId}`;
}

export function serializeMediaItem(row, genreIds = [], { uid = null, now = Date.now() } = {}) {
    const present = row.worked_by && row.worked_since > now - PRESENCE_WINDOW_MS;
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
        posterAuto: row.poster_auto === 1,
        status: row.status,
        genreIds,
        totalImages: row.total_images,
        reviewedImages: row.reviewed_images,
        approvedImages: row.approved_images,
        publishMode: row.publish_mode ?? "auto",
        published: row.published === 1,
        workedBy: present
            ? { uid: row.worked_by, name: row.worked_by_name ?? null, since: row.worked_since, isMine: row.worked_by === uid }
            : null,
        lastSyncedAt: row.last_synced_at,
        voteAverage: row.vote_average ?? null,
        voteCount: row.vote_count ?? null,
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
// No rating filters: the phone filters the curated pool by rating from the
// catalogue index, and the server only deals frames for the title it picked.
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
    published: "m.published = 1",
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
        target = null,
        excludeDailyFrom = null
    } = {}
) {
    const conditions = ["m.media_type = ?"];
    const bindings = [filters.mediaType];

    if (!includeUnapproved) {
        conditions.push("m.published = 1", "m.approved_images >= ?");
        bindings.push(filters.minApprovedImages);
    }

    // A film dealt at random before its day would give the daily puzzle away.
    if (excludeDailyFrom) {
        conditions.push("NOT EXISTS (SELECT 1 FROM daily_overrides d WHERE d.media_key = m.key AND d.date >= ?)");
        bindings.push(excludeDailyFrom);
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

// Where to look next: titles with frames nobody has judged, the ones already
// started first, then by popularity. Zero means "not in the queue", so the
// queue is a range scan on idx_media_work rather than a filtered sort.
export function workWeight({ status, publishMode, popularity, reviewed, unjudged }) {
    if (status === "rejected" || publishMode === "off" || unjudged === 0) return 0;
    return (reviewed > 0 ? 1_000_000 : 0) + popularity + 0.01;
}

// Whether players may be dealt the title, from the rule in schema.sql.
export function isPublished({ status, publishMode, posterURL, approved, unjudged }) {
    if (publishMode === "off" || status === "rejected" || !posterURL || approved < PUBLISH_MIN_FRAMES) return false;
    return publishMode === "on" || unjudged === 0;
}

// Recomputes everything a list screen reads off a title. Derived rather than
// hand-set so it cannot drift from the frames underneath, and read in one pass
// over this title's frames — writes are rare, list reads are not.
export async function refreshMediaCounters(env, key) {
    const item = await env.DB.prepare(
        "SELECT status, publish_mode, poster_url, popularity, work_weight, published FROM media_items WHERE key = ?"
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

    // 'rejected' is sticky: undoing it is `/catalog/items/{key}/reset`, never a
    // side effect of a verdict on some frame.
    const status = item.status === "rejected" ? "rejected" : counts.approved > 0 ? "approved" : item.status;
    const publishMode = item.publish_mode ?? "auto";
    const weight = workWeight({
        status,
        publishMode,
        popularity: item.popularity,
        reviewed: counts.reviewed,
        unjudged: counts.unjudged
    });
    const published = isPublished({
        status,
        publishMode,
        posterURL: item.poster_url,
        approved: counts.approved,
        unjudged: counts.unjudged
    }) ? 1 : 0;

    // These sit in indexes, and D1 bills a written row per index touched, so
    // they are only set when they actually move.
    const moved = [];
    const movedValues = [];
    for (const [column, value, current] of [
        ["status", status, item.status],
        ["work_weight", weight, item.work_weight],
        ["published", published, item.published]
    ]) {
        if (value === current) continue;
        moved.push(`${column} = ?`);
        movedValues.push(value);
    }

    const update = env.DB.prepare(
        `UPDATE media_items
         SET total_images = ?, reviewed_images = ?, approved_images = ?,
             pending_images = ?, unjudged_images = ?, untiered_approved = ?,
             preview_path = ?${moved.map((clause) => `, ${clause}`).join("")}
         WHERE key = ?`
    ).bind(
        counts.total, counts.reviewed, counts.approved,
        counts.pending, counts.unjudged, counts.untiered,
        preview?.file_path ?? null, ...movedValues, key
    );

    if (published === item.published) await update.run();
    else await env.DB.batch([update, markIndexDirtyStatement(env)]);
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
