// Screen-shaped reads and writes for the curation app: one request per screen,
// each with a known ceiling on rows read, since D1's free tier bills every row.
// Lists read the counters on the title row (see refreshMediaCounters).

import { badRequest, json, notFound, parseInteger, readJSON } from "../lib/http.js";
import { publicUser, requireRole } from "../lib/auth.js";
import {
    CURATION_FILTER_NAMES,
    MEDIA_TYPES,
    PRESENCE_WINDOW_MS,
    PUBLISH_MIN_FRAMES,
    REPORT_REASONS,
    buildCatalogQuery,
    catalogOrderBy,
    parseFilters,
    refreshMediaCounters,
    serializeImage,
    serializeMediaItem
} from "../lib/media.js";
import { limitByUser } from "../lib/limits.js";
import { SHOWCASE_LISTS, fetchShowcasePage, importMediaItem, searchTitles } from "../lib/tmdb.js";
import { applyVerdicts, parseVerdicts } from "../lib/verdicts.js";

const PAGE_LIMIT = 50;
const QUEUE_BADGE_CAP = 50;

// D1 binds at most 100 parameters, so key lists are capped well under that.
const KEY_LIST_LIMIT = 90;

export async function handleCurationScreens(request, env, segments, url, { user, config }) {
    const now = Date.now();
    const serialize = (row) => serializeMediaItem(row, [], { uid: user.uid, now });

    // GET /v1/curation/home — who I am, the knobs the client needs, badges
    if (segments[0] === "home" && request.method === "GET") {
        requireRole(user, "moderator");

        const [queue, reports] = await env.DB.batch([
            env.DB.prepare("SELECT COUNT(*) AS n FROM (SELECT 1 FROM media_items WHERE work_weight > 0 LIMIT ?)")
                .bind(QUEUE_BADGE_CAP),
            env.DB.prepare("SELECT COUNT(DISTINCT image_id) AS n FROM image_reports WHERE dismissed_at IS NULL")
        ]);

        const count = (result) => result.results[0]?.n ?? 0;
        const queueCount = count(queue);

        return json({
            user: publicUser(user),
            config: {
                targetApprovedFrames: config.targetApprovedFrames,
                publishMinFrames: PUBLISH_MIN_FRAMES
            },
            badges: {
                queue: queueCount,
                queueIsCapped: queueCount >= QUEUE_BADGE_CAP,
                reports: count(reports)
            }
        });
    }

    const screens = ["queue", "catalog", "items", "search", "showcase", "titles", "signals"];
    if (!screens.includes(segments[0])) return null;
    requireRole(user, "moderator");

    // GET /v1/curation/queue — titles with unjudged frames, started ones first.
    // Someone else's open workbench is skipped so two people are not dealt the
    // same title; opening it by hand is still allowed.
    if (segments[0] === "queue" && segments.length === 1 && request.method === "GET") {
        const mediaType = url.searchParams.get("mediaType");
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");
        const limit = parseInteger(url.searchParams.get("limit"), { fallback: 20, min: 1, max: PAGE_LIMIT });

        const rows = await env.DB.prepare(
            `SELECT * FROM media_items m
             WHERE m.work_weight > 0
               AND (?1 IS NULL OR m.media_type = ?1)
               AND NOT (m.worked_by IS NOT NULL AND m.worked_by != ?2 AND m.worked_since > ?3)
             ORDER BY m.work_weight DESC, m.key
             LIMIT ?4`
        ).bind(mediaType || null, user.uid, now - PRESENCE_WINDOW_MS, limit).all();

        return json({ items: rows.results.map(serialize) });
    }

    // GET /v1/curation/catalog — one page of titles with everything a row shows
    if (segments[0] === "catalog" && request.method === "GET") {
        const filters = parseFilters(url);
        const filter = url.searchParams.get("filter");
        if (filter && filter !== "all" && !CURATION_FILTER_NAMES.includes(filter)) {
            throw badRequest(`filter must be one of: all, ${CURATION_FILTER_NAMES.join(", ")}`);
        }
        const limit = parseInteger(url.searchParams.get("limit"), { fallback: PAGE_LIMIT, min: 1, max: PAGE_LIMIT });
        const offset = parseInteger(url.searchParams.get("offset"), { fallback: 0, min: 0 });

        const { where, bindings } = buildCatalogQuery(
            { ...filters, query: "" },
            { includeUnapproved: true, curationFilter: filter && filter !== "all" ? filter : null }
        );
        const order = catalogOrderBy(url.searchParams.get("sort"));

        const rows = await env.DB.prepare(
            `SELECT * FROM media_items m WHERE ${where} ORDER BY ${order.sql} LIMIT ? OFFSET ?`
        ).bind(...bindings, ...order.bindings, limit + 1, offset).all();

        return json({
            items: rows.results.slice(0, limit).map(serialize),
            offset,
            hasMore: rows.results.length > limit
        });
    }

    // GET /v1/curation/items?keys=a,b — known titles only, one row each
    if (segments[0] === "items" && segments.length === 1 && request.method === "GET") {
        const keys = [...new Set((url.searchParams.get("keys") || "").split(",").map((key) => key.trim()).filter(Boolean))];
        if (keys.length > KEY_LIST_LIMIT) throw badRequest(`At most ${KEY_LIST_LIMIT} keys per request`);

        return json({ items: (await loadItems(env, keys)).map(serialize) });
    }

    // GET /v1/curation/search?q= — TMDB's matching, our standing
    if (segments[0] === "search" && request.method === "GET") {
        const query = (url.searchParams.get("q") || "").trim().slice(0, 100);
        if (!query) return json({ results: [] });

        const mediaType = url.searchParams.get("mediaType");
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");

        // Each search spends a request against our TMDB key.
        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const hits = (await searchTitles(env, query))
            .filter((hit) => !mediaType || hit.mediaType === mediaType)
            .slice(0, 20);

        return json({ results: await withStanding(env, hits, serialize) });
    }

    // GET /v1/curation/showcase?list=known&mediaType=movie&page=1 — TMDB's lists
    // with our standing: the way into work that is not in the base yet.
    if (segments[0] === "showcase" && request.method === "GET") {
        const list = url.searchParams.get("list") || "known";
        if (!SHOWCASE_LISTS.includes(list)) throw badRequest(`list must be one of: ${SHOWCASE_LISTS.join(", ")}`);
        const mediaType = url.searchParams.get("mediaType") || "movie";
        if (!MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");
        const page = parseInteger(url.searchParams.get("page"), { fallback: 1, min: 1, max: 500 });
        const decade = parseInteger(url.searchParams.get("decade"), { min: 1900, max: 2100 });
        const genre = parseInteger(url.searchParams.get("genre"), { min: 1 });

        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const { hits, hasMore } = await fetchShowcasePage(env, { list, mediaType, page, decade, genre });
        return json({ results: await withStanding(env, hits, serialize), page, hasMore });
    }

    if (segments[0] === "titles" && segments.length === 3 && request.method === "POST") {
        const mediaKey = segments[1];

        // POST /v1/curation/titles/{key}/open — the workbench in one call:
        // imports a title TMDB has and we do not, and says who else is on it.
        if (segments[2] === "open") {
            const existing = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(mediaKey).first();

            if (!existing) {
                const [mediaType, rawId] = mediaKey.split("_");
                const tmdbId = Number.parseInt(rawId, 10);
                if (!MEDIA_TYPES.includes(mediaType) || !Number.isInteger(tmdbId)) {
                    throw notFound(`Unknown media item "${mediaKey}"`);
                }

                await limitByUser(env, user.uid, "IMPORT_LIMITER");
                await importMediaItem(env, mediaType, tmdbId, { addedBy: user.uid });
                await refreshMediaCounters(env, mediaKey);
            }

            const previous = existing ? serialize(existing).workedBy : null;

            const [marked, images] = await env.DB.batch([
                env.DB.prepare(
                    "UPDATE media_items SET worked_by = ?, worked_by_name = ?, worked_since = ? WHERE key = ? RETURNING *"
                ).bind(user.uid, user.display_name ?? null, now, mediaKey),
                env.DB.prepare("SELECT * FROM media_images WHERE media_key = ? ORDER BY tmdb_vote_average ASC, id").bind(mediaKey)
            ]);

            return json({
                item: serialize(marked.results[0]),
                images: images.results.map(serializeImage),
                imported: !existing,
                alsoWorking: previous && !previous.isMine ? previous : null
            });
        }

        // POST /v1/curation/titles/{key}/verdicts — what changed since the last
        // save. `close` also clears the workbench mark; `rejectRemaining` is the
        // "everything I did not take is out" of finishing a title.
        if (segments[2] === "verdicts") {
            const body = await readJSON(request);
            const verdicts = parseVerdicts(body.verdicts);

            const exists = await env.DB.prepare("SELECT key FROM media_items WHERE key = ?").bind(mediaKey).first();
            if (!exists) throw notFound(`Unknown media item "${mediaKey}"`);

            await limitByUser(env, user.uid, "WRITE_LIMITER");

            if (verdicts.length || body.rejectRemaining === true) {
                await applyVerdicts(env, {
                    mediaKey,
                    verdicts,
                    rejectRemaining: body.rejectRemaining === true,
                    moderatorUid: user.uid,
                    now
                });
            }

            const item = await markPresence(env, mediaKey, user, { close: body.close === true, now });
            return json({ item: serialize(item), applied: verdicts.length });
        }

        // POST /v1/curation/titles/{key}/close — leaving without changes
        if (segments[2] === "close") {
            const item = await markPresence(env, mediaKey, user, { close: true, now });
            if (!item) throw notFound(`Unknown media item "${mediaKey}"`);
            return json({ item: serialize(item) });
        }
    }

    // GET /v1/curation/signals/reports — open complaints, grouped by title
    if (segments[0] === "signals" && segments[1] === "reports" && request.method === "GET") {
        const rows = await env.DB.prepare(
            `SELECT r.image_id, r.reason, i.media_key
             FROM image_reports r
             JOIN media_images i ON i.id = r.image_id
             WHERE r.dismissed_at IS NULL
             ORDER BY r.created_at DESC
             LIMIT 500`
        ).all();

        const groups = new Map();
        for (const row of rows.results) {
            if (!groups.has(row.media_key)) {
                groups.set(row.media_key, { frameIds: new Set(), reportCount: 0, reasons: new Set() });
            }
            const group = groups.get(row.media_key);
            group.frameIds.add(row.image_id);
            group.reportCount += 1;
            if (REPORT_REASONS.includes(row.reason)) group.reasons.add(row.reason);
        }

        const items = await loadItems(env, [...groups.keys()].slice(0, KEY_LIST_LIMIT));

        return json({
            titles: items
                .map((row) => {
                    const group = groups.get(row.key);
                    return {
                        item: serialize(row),
                        frameIds: [...group.frameIds],
                        reportCount: group.reportCount,
                        reasons: [...group.reasons]
                    };
                })
                .sort((a, b) => b.reportCount - a.reportCount)
        });
    }

    return null;
}

async function loadItems(env, keys) {
    if (!keys.length) return [];
    const rows = await env.DB.prepare(
        `SELECT * FROM media_items WHERE key IN (${keys.map(() => "?").join(", ")})`
    ).bind(...keys).all();

    const byKey = new Map(rows.results.map((row) => [row.key, row]));
    return keys.map((key) => byKey.get(key)).filter(Boolean);
}

async function withStanding(env, hits, serialize) {
    const known = new Map((await loadItems(env, hits.map((hit) => hit.key))).map((row) => [row.key, row]));
    return hits.map((hit) => ({ ...hit, item: known.has(hit.key) ? serialize(known.get(hit.key)) : null }));
}

// A save keeps one's own mark fresh; leaving clears it, but only one's own:
// someone who opened the title since is still working on it.
async function markPresence(env, mediaKey, user, { close, now }) {
    const statement = close
        ? env.DB.prepare(
            `UPDATE media_items
             SET worked_by = CASE WHEN worked_by = ?1 THEN NULL ELSE worked_by END,
                 worked_by_name = CASE WHEN worked_by = ?1 THEN NULL ELSE worked_by_name END,
                 worked_since = CASE WHEN worked_by = ?1 THEN NULL ELSE worked_since END
             WHERE key = ?2 RETURNING *`
        ).bind(user.uid, mediaKey)
        : env.DB.prepare(
            "UPDATE media_items SET worked_since = CASE WHEN worked_by = ?1 THEN ?3 ELSE worked_since END WHERE key = ?2 RETURNING *"
        ).bind(user.uid, mediaKey, now);

    return (await statement.all()).results[0] ?? null;
}
