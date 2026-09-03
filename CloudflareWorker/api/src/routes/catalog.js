import { badRequest, json, notFound, parseInteger, readJSON, requireEnum } from "../lib/http.js";
import { authenticate, requireRole } from "../lib/auth.js";
import {
    MEDIA_TYPES,
    buildCatalogQuery,
    DIFFICULTY_TIERS,
    loadGenreIds,
    parseFilters,
    refreshMediaCounters,
    serializeImage,
    serializeMediaItem
} from "../lib/media.js";
import { fetchDiscoverPage, fetchPosterOptions, importMediaItem } from "../lib/tmdb.js";
import { limitByUser } from "../lib/limits.js";

const MAX_BULK_IMPORT = 20;
const MAX_BULK_VERDICTS = 300;

export async function handleCatalog(request, env, segments, url) {
    // GET /v1/catalog/items — browse the curated pool
    if (segments[0] === "items" && segments.length === 1 && request.method === "GET") {
        const user = await authenticate(request, env);

        const filters = parseFilters(url);
        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 50, min: 1, max: 200 });
        const offset = parseInteger(url.searchParams.get("offset"), { fallback: 0, min: 0 });

        // Only a moderator may see titles that are not playable yet — for a
        // player, "the catalogue" means what they can actually be dealt.
        const includeUnapproved =
            url.searchParams.get("includeUnapproved") === "true" && user.role !== "user";

        const { where, bindings } = buildCatalogQuery(filters, { includeUnapproved });

        const rows = await env.DB.prepare(
            `SELECT * FROM media_items m WHERE ${where} ORDER BY m.popularity DESC LIMIT ? OFFSET ?`
        ).bind(...bindings, limit, offset).all();

        const genres = await loadGenreIds(env, rows.results.map((row) => row.key));

        return json({
            items: rows.results.map((row) => serializeMediaItem(row, genres.get(row.key) || [])),
            limit,
            offset
        });
    }

    // GET /v1/catalog/count — exact size of the pool under these filters
    if (segments[0] === "count" && request.method === "GET") {
        const user = await authenticate(request, env);
        const filters = parseFilters(url);
        const excludeWatched = url.searchParams.get("excludeWatched") === "true";

        const { where, bindings } = buildCatalogQuery(filters, { uid: user.uid, excludeWatched });
        const row = await env.DB.prepare(`SELECT COUNT(*) AS count FROM media_items m WHERE ${where}`)
            .bind(...bindings)
            .first();

        return json({ count: row.count, exact: true });
    }

    // GET /v1/catalog/items/{key} — one title with every image and its state
    if (segments[0] === "items" && segments.length === 2 && request.method === "GET") {
        await authenticate(request, env);
        const key = segments[1];

        const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
        if (!item) throw notFound(`Unknown media item "${key}"`);

        const images = await env.DB.prepare(
            "SELECT * FROM media_images WHERE media_key = ? ORDER BY tmdb_vote_average ASC"
        ).bind(key).all();

        const genres = await loadGenreIds(env, [key]);

        return json({
            item: serializeMediaItem(item, genres.get(key) || []),
            images: images.results.map(serializeImage)
        });
    }

    // POST /v1/catalog/import — pull titles from TMDB into the catalogue
    if (segments[0] === "import" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        await limitByUser(env, user.uid, "IMPORT_LIMITER");

        const body = await readJSON(request);
        const mediaType = requireEnum(body, "mediaType", MEDIA_TYPES);
        const ids = Array.isArray(body.tmdbIds) ? body.tmdbIds.filter(Number.isInteger) : [];

        if (!ids.length) throw badRequest("tmdbIds must be a non-empty array of integers");

        // A Worker gets 50 subrequests per invocation on the free plan, so bulk
        // imports are chunked by the client rather than silently truncated here.
        if (ids.length > MAX_BULK_IMPORT) {
            throw badRequest(`At most ${MAX_BULK_IMPORT} titles can be imported per request`);
        }

        const imported = [];
        const failed = [];
        for (const tmdbId of ids) {
            try {
                const result = await importMediaItem(env, mediaType, tmdbId, { addedBy: user.uid });
                await refreshMediaCounters(env, result.key);
                imported.push(result);
            } catch (error) {
                failed.push({ tmdbId, reason: error.code || "import_failed" });
            }
        }

        return json({ imported, failed });
    }

    // POST /v1/catalog/import-popular — seed the catalogue from TMDB's own ranking
    if (segments[0] === "import-popular" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        await limitByUser(env, user.uid, "IMPORT_LIMITER");

        const body = await readJSON(request);
        const mediaType = requireEnum(body, "mediaType", MEDIA_TYPES);
        const page = Number.isInteger(body.page) ? body.page : 1;
        const limit = Math.min(Number.isInteger(body.limit) ? body.limit : MAX_BULK_IMPORT, MAX_BULK_IMPORT);

        const discover = await fetchDiscoverPage(env, mediaType, { page });
        const ids = discover.results.slice(0, limit).map((entry) => entry.id);

        const imported = [];
        const failed = [];
        for (const tmdbId of ids) {
            try {
                const result = await importMediaItem(env, mediaType, tmdbId, { addedBy: user.uid });
                await refreshMediaCounters(env, result.key);
                imported.push(result);
            } catch (error) {
                failed.push({ tmdbId, reason: error.code || "import_failed" });
            }
        }

        return json({ page, imported, failed });
    }

    // GET /v1/catalog/items/{key}/posters — poster candidates for the ticket screen
    if (segments[0] === "items" && segments[2] === "posters" && request.method === "GET") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(segments[1]).first();
        if (!item) throw notFound(`Unknown media item "${segments[1]}"`);

        return json({ posters: await fetchPosterOptions(env, item.media_type, item.tmdb_id) });
    }

    // PATCH /v1/catalog/items/{key} — set the poster or finalise the title
    if (segments[0] === "items" && segments.length === 2 && request.method === "PATCH") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");

        const key = segments[1];
        const body = await readJSON(request);

        if (typeof body.posterURL === "string" || body.posterURL === null) {
            await env.DB.prepare("UPDATE media_items SET poster_url = ? WHERE key = ?").bind(body.posterURL, key).run();
        }

        if (typeof body.adminFinalized === "boolean") {
            await env.DB.prepare(
                "UPDATE media_items SET admin_finalized = ?, finalized_at = ?, finalized_by = ? WHERE key = ?"
            ).bind(body.adminFinalized ? 1 : 0, body.adminFinalized ? Date.now() : null, body.adminFinalized ? user.uid : null, key).run();
        }

        const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
        if (!item) throw notFound(`Unknown media item "${key}"`);

        const genres = await loadGenreIds(env, [key]);
        return json(serializeMediaItem(item, genres.get(key) || []));
    }

    // POST /v1/catalog/items/{key}/curate — decide a whole title in one call
    //
    // The per-frame endpoints are right for the community queue, where a player
    // genuinely looks at one frame at a time. They are wrong for a moderator: a
    // popular film can carry 170 backdrops, and settling it frame by frame
    // would be 170 requests out of a 100k daily budget shared with the image
    // proxy. Here the whole title is one request, and identical verdicts are
    // collapsed into a single UPDATE each so the query count stays flat no
    // matter how many frames there are — D1 allows only 50 queries per
    // invocation on the free plan.
    if (segments[0] === "items" && segments[2] === "curate" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");
        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const key = segments[1];
        const item = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(key).first();
        if (!item) throw notFound(`Unknown media item "${key}"`);

        const body = await readJSON(request);
        const verdicts = Array.isArray(body.verdicts) ? body.verdicts : [];
        if (verdicts.length > MAX_BULK_VERDICTS) {
            throw badRequest(`At most ${MAX_BULK_VERDICTS} frames per request`);
        }

        // Grouped by the exact change being applied, so N frames sharing a
        // verdict cost one statement rather than N.
        const groups = new Map();
        for (const verdict of verdicts) {
            const imageId = Number.parseInt(verdict.imageId, 10);
            if (!Number.isInteger(imageId)) throw badRequest("Each verdict needs an integer imageId");

            // Clearing a lock has to consult the votes again, which is a
            // per-frame job — the single-frame endpoint handles it.
            if (!["approved", "rejected"].includes(verdict.status)) {
                throw badRequest('Each verdict status must be "approved" or "rejected"');
            }

            const tier = verdict.difficultyTier === undefined ? undefined : verdict.difficultyTier;
            if (tier !== undefined && tier !== null && !DIFFICULTY_TIERS.includes(tier)) {
                throw badRequest(`difficultyTier must be null or one of: ${DIFFICULTY_TIERS.join(", ")}`);
            }

            const groupKey = `${verdict.status}|${tier === undefined ? "keep" : tier}`;
            if (!groups.has(groupKey)) groups.set(groupKey, { status: verdict.status, tier, ids: [] });
            groups.get(groupKey).ids.push(imageId);
        }

        const now = Date.now();
        const statements = [];

        for (const { status, tier, ids } of groups.values()) {
            const placeholders = ids.map(() => "?").join(", ");
            // A locked frame's status is its lock, so it can be written in the
            // same statement instead of recomputed afterwards.
            const tierClause = tier === undefined ? "" : ", difficulty_tier = ?";
            const bindings = tier === undefined
                ? [status, status, user.uid, now, key, ...ids]
                : [status, status, user.uid, now, tier, key, ...ids];

            statements.push(
                env.DB.prepare(
                    `UPDATE media_images
                     SET status = ?, moderator_status = ?, moderator_uid = ?, moderator_at = ?${tierClause}
                     WHERE media_key = ? AND id IN (${placeholders})`
                ).bind(...bindings)
            );
        }

        // "Everything I did not tick is out" — the common ending to reviewing a
        // title with far more frames than a round will ever need.
        if (body.rejectRemaining === true) {
            const reviewed = verdicts.map((verdict) => Number.parseInt(verdict.imageId, 10));
            const exclusion = reviewed.length ? `AND id NOT IN (${reviewed.map(() => "?").join(", ")})` : "";

            statements.push(
                env.DB.prepare(
                    `UPDATE media_images
                     SET status = 'rejected', moderator_status = 'rejected', moderator_uid = ?, moderator_at = ?
                     WHERE media_key = ? AND moderator_status IS NULL ${exclusion}`
                ).bind(user.uid, now, key, ...reviewed)
            );
        }

        if (statements.length) await env.DB.batch(statements);
        await refreshMediaCounters(env, key);

        const refreshed = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
        const genres = await loadGenreIds(env, [key]);

        return json({
            item: serializeMediaItem(refreshed, genres.get(key) || []),
            applied: verdicts.length,
            rejectedRemaining: body.rejectRemaining === true
        });
    }

    return null;
}
