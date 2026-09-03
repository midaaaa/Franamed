# Franamed API

Cloudflare Worker + D1. Serves everything the app needs beyond TMDB itself:
accounts, the curated catalogue, curation, playlists, the daily puzzle, and the
attempt economy.

The TMDB image proxy stays a separate worker (`../tmdb-proxy`) — this one never
serves images, only the paths to them.

## Deploy

Wrangler needs npm, which is blocked on the same networks TMDB is. Turn the VPN
or WARP on first.

```bash
npm i -g wrangler && wrangler login
```

Create the database and paste the printed `database_id` into `wrangler.toml`:

```bash
wrangler d1 create franamed
```

Apply the schema:

```bash
wrangler d1 execute franamed --remote --file=./schema.sql
```

Set the three secrets. `JWT_SECRET` must be long random bytes — anything
guessable there lets someone mint their own access tokens:

```bash
openssl rand -base64 48 | wrangler secret put JWT_SECRET
wrangler secret put TMDB_API_KEY
wrangler secret put APPLE_BUNDLE_ID
```

Deploy:

```bash
wrangler deploy
```

Then point the app at the printed URL in `BackendConfiguration.default`.

## First run

The very first account created becomes `admin`, so whoever opens the app first
after a fresh deploy can grant roles. Everyone after that is a plain `user`.

Seed the catalogue from the backend tab in the app ("Импортировать 20
популярных"), or directly:

```bash
curl -X POST "$API/v1/catalog/import-popular" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mediaType":"movie","page":1,"limit":20}'
```

Imported frames arrive as `pending`. Nothing is playable until it is approved,
either through the curation queue or by a moderator setting the status.

## Routes

| Method | Path | Who |
|---|---|---|
| POST | `/v1/auth/anonymous` | anyone |
| POST | `/v1/auth/apple` | anyone |
| POST | `/v1/auth/refresh` | anyone holding a refresh token |
| POST | `/v1/auth/link-apple` | signed in |
| POST | `/v1/auth/logout` | signed in |
| GET | `/v1/auth/me` | signed in |
| GET | `/v1/round/next` | signed in |

`/v1/round/next` inside a playlist takes `pick=next` (straight down the curator's
order — the 1-to-100 walk), `pick=shuffle` (unplayed in order, then the ones
answered wrong, then genuine random once everything is right), or an explicit
`mediaKey` to replay one entry. It answers with `position` / `playlistTotal`, and
always with `spareFrames`: approved frames beyond the six in play, so a frame
deleted from TMDB can be swapped on device without another request. A title with
exactly six approved frames has no spares — which is why the curation target
(`targetApprovedFrames`, 12) sits above the playability threshold (6).
| GET | `/v1/catalog/items`, `/count`, `/items/{key}` | signed in |
| POST | `/v1/catalog/import`, `/import-popular` | moderator |
| POST | `/v1/catalog/items/{key}/curate` | moderator |
| PATCH | `/v1/catalog/items/{key}` | moderator |
| GET | `/v1/curation/queue` | signed in |
| POST | `/v1/curation/vote`, `/report` | signed in |
| PATCH | `/v1/curation/images/{id}` | signed in (hash) / moderator (rest) |
| POST | `/v1/curation/images/{id}/lock`, `/dismiss-disputes` | moderator |
| GET | `/v1/curation/reports`, `/contested` | moderator |
| GET/POST | `/v1/playlists` | signed in / moderator |
| GET/PATCH | `/v1/playlists/{id}` | signed in / moderator |
| PUT | `/v1/playlists/{id}/items` | moderator |
| POST | `/v1/playlists/{id}/progress`, `/reset` | signed in |
| GET/POST/DELETE | `/v1/profile/...` | signed in |
| GET | `/v1/admin/config` | signed in |
| PATCH | `/v1/admin/config`, POST `/v1/admin/roles` | admin |
| GET | `/v1/admin/users`, `/stats`, `/daily` | moderator |
| PUT | `/v1/admin/daily/{date}` | moderator |

## Abuse

Two defences, because neither is enough alone.

**Rate limiting** (`src/lib/limits.js`) sits on sign-in, writes and imports. Its
counters are per Cloudflare location and eventually consistent, so a burst leaks
through before it bites — measured at 19 of 40 rapid sign-ins getting through
before the first 429. It caps sustained hammering, not patience.

**Vote weight earned by playing** is the one that matters. Weighted voting
assumes accounts are scarce; anonymous accounts are free, so a hundred throwaway
sign-ins could otherwise swing any frame. A vote counts for nothing until the
account has played `voteWeightMinRounds` rounds (default 5). Minting accounts is
cheap; playing five rounds on each is not. Attempts are still awarded while the
weight is zero, since curating is how a new player unlocks rounds.

A moderator lock overrides both: votes and reports keep landing on a locked
frame — that is how a moderator learns they were wrong, surfaced by
`/v1/curation/contested` — they just stop deciding.

## Free plan headroom

100k Worker requests/day account-wide — shared with the image proxy, which is
what will run out first, since a round pulls six frames through it. D1 allows
5M row reads and 100k row writes a day, 500 MB per database. CPU is capped at
10 ms per request, which is why perceptual hashes are computed on the device and
bulk imports are chunked at 20 titles.
