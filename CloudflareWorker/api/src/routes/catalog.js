import { badRequest, json, notFound, optionalString, parseInteger, readJSON, requireEnum } from "../lib/http.js";
import { authenticate, requireRole, roleRank } from "../lib/auth.js";
import {
    CURATION_FILTER_NAMES,
    MEDIA_TYPES,
    buildCatalogQuery,
    catalogOrderBy,
    loadGenreIds,
    parseFilters,
    recomputeTitleImageStatuses,
    refreshMediaCounters,
    serializeImage,
    serializeMediaItem
} from "../lib/media.js";
import { readConfig } from "../lib/config.js";
import { utcDateString } from "../lib/daily.js";
import { fetchDiscoverPage, fetchPosterOptions, importMediaItem } from "../lib/tmdb.js";
import { limitByUser } from "../lib/limits.js";
import { applyVerdicts, parseVerdicts } from "../lib/verdicts.js";

const MAX_BULK_IMPORT = 20;

export async function handleCatalog(request, env, segments, url) {
    // GET /v1/catalog/items — browse the curated pool
    if (segments[0] === "items" && segments.length === 1 && request.method === "GET") {
        const user = await authenticate(request, env);

        const filters = parseFilters(url);
        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 50, min: 1, max: 200 });
        const offset = parseInteger(url.searchParams.get("offset"), { fallback: 0, min: 0 });

        // For a player, "the catalogue" means what they can actually be dealt.
        const curates = roleRank(user.role) >= roleRank("curator");

        const curationFilter = url.searchParams.get("curate");
        if (curationFilter && !CURATION_FILTER_NAMES.includes(curationFilter)) {
            throw badRequest(`curate must be one of: ${CURATION_FILTER_NAMES.join(", ")}`);
        }
        if (curationFilter && !curates) throw badRequest("Curation filters need a curator role");

        // Every curator filter asks about unfinished work, so it implies the
        // unfinished titles; requiring both flags would only return empty pages.
        const includeUnapproved =
            curates && (curationFilter !== null || url.searchParams.get("includeUnapproved") === "true");

        const config = curates ? await readConfig(env) : null;

        const { where, bindings } = buildCatalogQuery(filters, {
            includeUnapproved,
            curationFilter,
            includeRejected: curates && url.searchParams.get("includeRejected") === "true",
            target: config?.targetApprovedFrames ?? null
        });

        // "Where is the work" needs the target to mean anything, so for everyone
        // else it falls back to popularity rather than an invented one.
        const order = catalogOrderBy(curates ? url.searchParams.get("sort") : null, {
            target: Math.max(1, config?.targetApprovedFrames ?? 1)
        });

        const rows = await env.DB.prepare(
            `SELECT * FROM media_items m WHERE ${where} ORDER BY ${order.sql} LIMIT ? OFFSET ?`
        ).bind(...bindings, ...order.bindings, limit, offset).all();

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

    // POST /v1/catalog/items/{key}/reset — drop every moderator verdict and
    // re-derive each frame from the votes and reports that remain.
    //
    // The insurance policy for `rejectRemaining`: one mis-aimed sweep locks 158
    // frames and clearing a lock is per-frame. Un-rejects the title too —
    // resetting means starting over, not starting over somewhere unplayable.
    if (segments[0] === "items" && segments[2] === "reset" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");
        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const key = segments[1];
        const item = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(key).first();
        if (!item) throw notFound(`Unknown media item "${key}"`);

        const config = await readConfig(env);

        await env.DB.batch([
            env.DB.prepare(
                `UPDATE media_images
                 SET moderator_status = NULL, moderator_uid = NULL, moderator_at = NULL
                 WHERE media_key = ?`
            ).bind(key),
            env.DB.prepare(
                `UPDATE media_items
                 SET status = 'pending', rejected_at = NULL, rejected_by = NULL, rejected_reason = NULL
                 WHERE key = ?`
            ).bind(key)
        ]);

        await recomputeTitleImageStatuses(env, key, {
            autoHideReportWeight: config.autoHideReportWeight
        });

        const refreshed = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
        const genres = await loadGenreIds(env, [key]);
        return json({ item: serializeMediaItem(refreshed, genres.get(key) || []) });
    }

    // POST /v1/catalog/items/{key}/reject — throw the whole title out.
    //
    // A decision about the film, not its frames: they keep their verdicts,
    // because reinstating the title does not make that work wrong.
    if (segments[0] === "items" && segments[2] === "reject" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");
        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const key = segments[1];
        const item = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(key).first();
        if (!item) throw notFound(`Unknown media item "${key}"`);

        const body = await readJSON(request).catch(() => ({}));

        await env.DB.prepare(
            `UPDATE media_items
             SET status = 'rejected', rejected_at = ?, rejected_by = ?, rejected_reason = ?
             WHERE key = ?`
        ).bind(Date.now(), user.uid, optionalString(body, "reason", { maxLength: 300 }), key).run();

        // Past days carry results, so only the ones still ahead are released.
        await env.DB.prepare(
            "DELETE FROM daily_overrides WHERE media_key = ? AND date > ?"
        ).bind(key, utcDateString()).run();

        const refreshed = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
        const genres = await loadGenreIds(env, [key]);
        return json({ item: serializeMediaItem(refreshed, genres.get(key) || []) });
    }

    // POST /v1/catalog/items/{key}/reimport — pull this title from TMDB again.
    // Safe to repeat: the import upserts and existing rows keep their curation
    // state, so it only adds frames TMDB has published since.
    if (segments[0] === "items" && segments[2] === "reimport" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");
        await limitByUser(env, user.uid, "IMPORT_LIMITER");

        const key = segments[1];
        const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
        if (!item) throw notFound(`Unknown media item "${key}"`);

        const before = await env.DB.prepare(
            "SELECT COUNT(*) AS count FROM media_images WHERE media_key = ?"
        ).bind(key).first();

        await importMediaItem(env, item.media_type, item.tmdb_id, { addedBy: item.added_by });
        await refreshMediaCounters(env, key);

        const after = await env.DB.prepare(
            "SELECT COUNT(*) AS count FROM media_images WHERE media_key = ?"
        ).bind(key).first();

        const refreshed = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(key).first();
        const genres = await loadGenreIds(env, [key]);

        return json({
            item: serializeMediaItem(refreshed, genres.get(key) || []),
            newFrames: after.count - before.count,
            totalFrames: after.count
        });
    }

    // POST /v1/catalog/items/{key}/curate — decide a whole title in one call.
    // A moderator settling 170 backdrops frame by frame would be 170 requests.
    if (segments[0] === "items" && segments[2] === "curate" && request.method === "POST") {
        const user = await authenticate(request, env);
        requireRole(user, "moderator");
        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const key = segments[1];
        const item = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(key).first();
        if (!item) throw notFound(`Unknown media item "${key}"`);

        const body = await readJSON(request);
        const verdicts = parseVerdicts(body.verdicts);

        await applyVerdicts(env, {
            mediaKey: key,
            verdicts,
            rejectRemaining: body.rejectRemaining === true,
            moderatorUid: user.uid
        });

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
