// Screen-shaped reads for the curation app: one request per screen, each with a
// known ceiling on rows read, since D1's free tier bills every row. Lists read
// the counters on the title row (see refreshMediaCounters) and stop at LIMIT.

import { badRequest, json, notFound, parseInteger, readJSON } from "../lib/http.js";
import { publicUser, requireRole, roleRank } from "../lib/auth.js";
import { acquireLease, canTakeOver, loadLease, serializeLease, takeNotices, takeOverLease } from "../lib/leases.js";
import {
    CURATION_FILTER_NAMES,
    MEDIA_TYPES,
    REPORT_REASONS,
    buildCatalogQuery,
    catalogOrderBy,
    parseFilters,
    serializeImage,
    serializeMediaItem
} from "../lib/media.js";
import { limitByUser } from "../lib/limits.js";
import { searchTitles } from "../lib/tmdb.js";

const PAGE_LIMIT = 50;
const QUEUE_BADGE_CAP = 50;

// D1 binds at most 100 parameters, so key lists are capped well under that.
const KEY_LIST_LIMIT = 90;

export async function handleCurationScreens(request, env, segments, url, { user, config, windowMs }) {
    const now = Date.now();

    // GET /v1/curation/home — who I am, the knobs the client needs, badges, notices
    if (segments[0] === "home" && request.method === "GET") {
        const moderates = roleRank(user.role) >= roleRank("moderator");

        const [queue, reviews, mine, reports] = await env.DB.batch([
            env.DB.prepare(
                `SELECT COUNT(*) AS n FROM (
                     SELECT 1 FROM media_items m
                     WHERE m.work_weight > 0
                       AND NOT EXISTS (SELECT 1 FROM title_leases l
                                       WHERE l.media_key = m.key AND l.released_at IS NULL AND l.touched_at > ?1 AND l.uid != ?2)
                       AND NOT EXISTS (SELECT 1 FROM curation_batches b WHERE b.media_key = m.key AND b.state = 'pending')
                     LIMIT ?3)`
            ).bind(now - windowMs, user.uid, QUEUE_BADGE_CAP),
            env.DB.prepare("SELECT COUNT(*) AS n FROM curation_batches WHERE state = 'pending'"),
            env.DB.prepare("SELECT COUNT(*) AS n FROM curation_batches WHERE uid = ? AND state = 'pending'").bind(user.uid),
            env.DB.prepare("SELECT COUNT(DISTINCT image_id) AS n FROM image_reports WHERE dismissed_at IS NULL")
        ]);

        const count = (result) => result.results[0]?.n ?? 0;
        const queueCount = count(queue);

        return json({
            user: publicUser(user),
            config: {
                targetApprovedFrames: config.targetApprovedFrames,
                curationLeaseMinutes: config.curationLeaseMinutes,
                curationHeartbeatSeconds: config.curationHeartbeatSeconds,
                curationEnabled: config.curationEnabled
            },
            badges: {
                queue: queueCount,
                queueIsCapped: queueCount >= QUEUE_BADGE_CAP,
                reviews: moderates ? count(reviews) : 0,
                mine: count(mine),
                reports: moderates ? count(reports) : 0
            },
            notices: await takeNotices(env, user.uid, { now })
        });
    }

    // GET /v1/curation/catalog — one page of titles with everything a row shows
    if (segments[0] === "catalog" && request.method === "GET") {
        requireRole(user, "curator");

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

        const page = rows.results.slice(0, limit);
        return json({
            items: await withWorkState(env, page, { user, now, windowMs }),
            offset,
            hasMore: rows.results.length > limit
        });
    }

    // GET /v1/curation/items?keys=a,b — known titles only, one row each
    if (segments[0] === "items" && segments.length === 1 && request.method === "GET") {
        requireRole(user, "curator");

        const keys = [...new Set((url.searchParams.get("keys") || "").split(",").map((key) => key.trim()).filter(Boolean))];
        if (keys.length > KEY_LIST_LIMIT) throw badRequest(`At most ${KEY_LIST_LIMIT} keys per request`);

        return json({ items: await withWorkState(env, await loadItems(env, keys), { user, now, windowMs }) });
    }

    // GET /v1/curation/search?q= — TMDB's matching, our standing
    if (segments[0] === "search" && request.method === "GET") {
        requireRole(user, "moderator");

        const query = (url.searchParams.get("q") || "").trim().slice(0, 100);
        if (!query) return json({ results: [] });

        const mediaType = url.searchParams.get("mediaType");
        if (mediaType && !MEDIA_TYPES.includes(mediaType)) throw badRequest("Unknown media type");

        // Each search spends a request against our TMDB key.
        await limitByUser(env, user.uid, "WRITE_LIMITER");

        const hits = (await searchTitles(env, query))
            .filter((hit) => !mediaType || hit.mediaType === mediaType)
            .slice(0, 20);

        const known = await withWorkState(env, await loadItems(env, hits.map((hit) => hit.key)), { user, now, windowMs });
        const byKey = new Map(known.map((item) => [item.key, item]));

        return json({ results: hits.map((hit) => ({ ...hit, item: byKey.get(hit.key) ?? null })) });
    }

    // POST /v1/curation/titles/{key}/open — the lease and the workbench in one call
    if (segments[0] === "titles" && segments[2] === "open" && request.method === "POST") {
        requireRole(user, "curator");

        const mediaKey = segments[1];
        const item = await env.DB.prepare("SELECT * FROM media_items WHERE key = ?").bind(mediaKey).first();
        if (!item) throw notFound(`Unknown media item "${mediaKey}"`);

        const body = await readJSON(request).catch(() => ({}));
        let lease = await acquireLease(env, user, mediaKey, { now, windowMs });

        if (!lease) {
            const holder = await loadLease(env, mediaKey);
            const mayTakeOver = Boolean(holder && canTakeOver(user, holder));

            if (body.takeover === true && mayTakeOver) {
                lease = await takeOverLease(env, user, holder, mediaKey, { reason: body.reason, now });
            }

            // Not an error: "someone else is here" is an answer the screen shows,
            // and a 409 body is where clients tend to lose it.
            if (!lease) {
                return json({
                    status: "held",
                    item: serializeMediaItem(item),
                    lease: serializeLease(holder, { now, windowMs, uid: user.uid }),
                    canTakeOver: mayTakeOver
                });
            }
        }

        const [images, pending] = await env.DB.batch([
            env.DB.prepare("SELECT * FROM media_images WHERE media_key = ? ORDER BY tmdb_vote_average ASC, id").bind(mediaKey),
            env.DB.prepare("SELECT id FROM curation_batches WHERE media_key = ? AND state = 'pending'").bind(mediaKey)
        ]);

        return json({
            status: "granted",
            item: serializeMediaItem(item),
            images: images.results.map(serializeImage),
            lease: serializeLease({ ...lease, display_name: user.display_name }, { now, windowMs, uid: user.uid }),
            pendingBatchId: pending.results[0]?.id ?? null,
            heartbeatSeconds: config.curationHeartbeatSeconds
        });
    }

    // GET /v1/curation/signals/reports — open complaints, grouped by title
    if (segments[0] === "signals" && segments[1] === "reports" && request.method === "GET") {
        requireRole(user, "moderator");

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

        const keys = [...groups.keys()].slice(0, KEY_LIST_LIMIT);
        const items = await withWorkState(env, await loadItems(env, keys), { user, now, windowMs });

        return json({
            titles: items
                .map((item) => {
                    const group = groups.get(item.key);
                    return {
                        item,
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

// The two facts a list row needs besides the title itself: who is on it, and
// whether a batch is waiting. Primary-key and partial-index probes, one per row.
async function withWorkState(env, rows, { user, now, windowMs }) {
    if (!rows.length) return [];
    const keys = rows.map((row) => row.key);
    const placeholders = keys.map(() => "?").join(", ");

    const [leases, batches] = await env.DB.batch([
        env.DB.prepare(
            `SELECT l.*, u.display_name FROM title_leases l LEFT JOIN users u ON u.uid = l.uid
             WHERE l.media_key IN (${placeholders}) AND l.released_at IS NULL AND l.touched_at > ?`
        ).bind(...keys, now - windowMs),
        env.DB.prepare(
            `SELECT media_key, id FROM curation_batches WHERE state = 'pending' AND media_key IN (${placeholders})`
        ).bind(...keys)
    ]);

    const leaseByKey = new Map(leases.results.map((row) => [row.media_key, row]));
    const batchByKey = new Map(batches.results.map((row) => [row.media_key, row.id]));

    return rows.map((row) => ({
        ...serializeMediaItem(row),
        lease: leaseByKey.has(row.key) ? serializeLease(leaseByKey.get(row.key), { now, windowMs, uid: user.uid }) : null,
        pendingBatchId: batchByKey.get(row.key) ?? null
    }));
}
