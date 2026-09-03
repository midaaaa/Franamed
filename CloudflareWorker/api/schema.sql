-- Franamed backend schema (Cloudflare D1 / SQLite)
--
-- Naming: media items are keyed by "{type}_{tmdbId}" ("movie_603", "tv_1399"),
-- because TMDB uses separate id spaces for movies and shows.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------- accounts

CREATE TABLE IF NOT EXISTS users (
    uid                       TEXT PRIMARY KEY,
    role                      TEXT    NOT NULL DEFAULT 'user',   -- user | moderator | admin
    report_multiplier         REAL    NOT NULL DEFAULT 1.0,
    display_name              TEXT,
    is_anonymous              INTEGER NOT NULL DEFAULT 1,
    created_at                INTEGER NOT NULL,

    -- daily economy
    daily_streak              INTEGER NOT NULL DEFAULT 0,
    longest_streak            INTEGER NOT NULL DEFAULT 0,
    last_daily_completed_date TEXT,                              -- YYYY-MM-DD
    bonus_attempts_available  INTEGER NOT NULL DEFAULT 0,
    attempts_used_today       INTEGER NOT NULL DEFAULT 0,
    last_attempt_reset_date   TEXT
);

-- One row per way of signing in. Linking an anonymous account to Apple just
-- adds a second row pointing at the same uid, so progress survives the upgrade.
CREATE TABLE IF NOT EXISTS identities (
    provider   TEXT NOT NULL,                                    -- anonymous | apple
    subject    TEXT NOT NULL,                                    -- device id | Apple "sub"
    uid        TEXT NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (provider, subject)
);
CREATE INDEX IF NOT EXISTS idx_identities_uid ON identities(uid);

-- Only the SHA-256 of a refresh token is stored, never the token itself.
CREATE TABLE IF NOT EXISTS refresh_tokens (
    token_hash TEXT PRIMARY KEY,
    uid        TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    issued_at  INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    revoked_at INTEGER,
    user_agent TEXT
);
CREATE INDEX IF NOT EXISTS idx_refresh_uid ON refresh_tokens(uid);

-- ---------------------------------------------------------------- catalog

CREATE TABLE IF NOT EXISTS media_items (
    key               TEXT PRIMARY KEY,
    tmdb_id           INTEGER NOT NULL,
    media_type        TEXT    NOT NULL,                          -- movie | tv
    title             TEXT    NOT NULL,
    original_title    TEXT    NOT NULL,
    release_year      INTEGER,
    original_language TEXT,
    popularity        REAL    NOT NULL DEFAULT 0,
    poster_url        TEXT,

    status            TEXT    NOT NULL DEFAULT 'pending',        -- pending | approved | rejected
    total_images      INTEGER NOT NULL DEFAULT 0,
    reviewed_images   INTEGER NOT NULL DEFAULT 0,
    approved_images   INTEGER NOT NULL DEFAULT 0,

    admin_finalized   INTEGER NOT NULL DEFAULT 0,
    finalized_at      INTEGER,
    finalized_by      TEXT,

    added_by          TEXT,
    last_synced_at    INTEGER,
    created_at        INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_media_type_status ON media_items(media_type, status);
CREATE INDEX IF NOT EXISTS idx_media_year        ON media_items(release_year);
CREATE INDEX IF NOT EXISTS idx_media_language    ON media_items(original_language);
CREATE INDEX IF NOT EXISTS idx_media_popularity  ON media_items(popularity DESC);

-- Genres as a join table rather than a serialised array: lets the database do
-- the filtering, which is what removed the need to ship the whole catalogue to
-- the client and filter it in Swift.
CREATE TABLE IF NOT EXISTS media_genres (
    media_key TEXT    NOT NULL REFERENCES media_items(key) ON DELETE CASCADE,
    genre_id  INTEGER NOT NULL,
    PRIMARY KEY (media_key, genre_id)
);
CREATE INDEX IF NOT EXISTS idx_media_genres_genre ON media_genres(genre_id);

CREATE TABLE IF NOT EXISTS media_images (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    media_key         TEXT    NOT NULL REFERENCES media_items(key) ON DELETE CASCADE,
    file_path         TEXT    NOT NULL,                          -- TMDB path, e.g. "/abc.jpg"
    status            TEXT    NOT NULL DEFAULT 'pending',        -- pending | approved | rejected
    report_weight     REAL    NOT NULL DEFAULT 0,

    perceptual_hash   TEXT,                                      -- 64-bit dHash as hex, computed on device
    clustered_with    TEXT,                                      -- leader's file_path; NULL when leader/unclustered

    difficulty_tier   TEXT,                                      -- hard | medium | easy
    difficulty_rank   INTEGER,                                   -- optional exact 1..6 override

    -- A moderator verdict community voting cannot overturn. Votes and reports
    -- keep accruing on a locked frame, they just stop deciding its status.
    moderator_status  TEXT,                                      -- approved | rejected, NULL = not locked
    moderator_uid     TEXT,
    moderator_at      INTEGER,
    disputes_dismissed_at    INTEGER,
    disputes_dismissed_count INTEGER NOT NULL DEFAULT 0,

    tmdb_vote_average REAL    NOT NULL DEFAULT 0,
    tmdb_vote_count   INTEGER NOT NULL DEFAULT 0,
    width             INTEGER,
    height            INTEGER,
    aspect_ratio      REAL,
    created_at        INTEGER NOT NULL,
    UNIQUE (media_key, file_path)
);
CREATE INDEX IF NOT EXISTS idx_images_media  ON media_images(media_key);
CREATE INDEX IF NOT EXISTS idx_images_status ON media_images(status);
CREATE INDEX IF NOT EXISTS idx_images_locked ON media_images(moderator_status);
CREATE INDEX IF NOT EXISTS idx_media_title  ON media_items(title);

-- Votes are per user so a vote can be changed: the old weight is subtracted and
-- the new one added, instead of an anonymous counter that can only go up.
CREATE TABLE IF NOT EXISTS image_votes (
    image_id   INTEGER NOT NULL REFERENCES media_images(id) ON DELETE CASCADE,
    uid        TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    verdict    TEXT    NOT NULL,                                 -- approve | reject
    weight     REAL    NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (image_id, uid)
);

CREATE TABLE IF NOT EXISTS image_reports (
    image_id   INTEGER NOT NULL REFERENCES media_images(id) ON DELETE CASCADE,
    uid        TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    reason     TEXT    NOT NULL,                                 -- poster | not_a_frame | bad_quality | unclear
    weight     REAL    NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (image_id, uid)
);
CREATE INDEX IF NOT EXISTS idx_reports_created ON image_reports(created_at DESC);

-- ---------------------------------------------------------------- playlists

CREATE TABLE IF NOT EXISTS playlists (
    id              TEXT PRIMARY KEY,
    title           TEXT    NOT NULL,
    description     TEXT,
    cover_image_url TEXT,
    media_type      TEXT    NOT NULL,                            -- single type per playlist, by design
    source          TEXT    NOT NULL DEFAULT 'curated',          -- curated | tmdb
    allow_uncurated INTEGER NOT NULL DEFAULT 0,
    published       INTEGER NOT NULL DEFAULT 0,
    created_by      TEXT,
    created_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlist_items (
    playlist_id TEXT    NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    media_key   TEXT    NOT NULL,
    position    INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, media_key)
);

-- Absence of a row means "notStarted" — no need to write a row per movie up front.
CREATE TABLE IF NOT EXISTS playlist_progress (
    uid           TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    playlist_id   TEXT    NOT NULL,
    media_key     TEXT    NOT NULL,
    state         TEXT    NOT NULL,                              -- inProgress | completed
    attempts_used INTEGER NOT NULL DEFAULT 0,
    was_correct   INTEGER,
    updated_at    INTEGER NOT NULL,
    PRIMARY KEY (uid, playlist_id, media_key)
);

CREATE TABLE IF NOT EXISTS playlist_completions (
    uid             TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    playlist_id     TEXT    NOT NULL,
    times_completed INTEGER NOT NULL DEFAULT 0,
    completed_at    INTEGER,
    PRIMARY KEY (uid, playlist_id)
);

-- ---------------------------------------------------------------- daily

CREATE TABLE IF NOT EXISTS daily_overrides (
    date       TEXT PRIMARY KEY,                                 -- YYYY-MM-DD
    media_key  TEXT    NOT NULL,
    created_by TEXT,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_results (
    uid           TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    date          TEXT    NOT NULL,
    media_key     TEXT    NOT NULL,
    was_correct   INTEGER NOT NULL,
    attempts_used INTEGER NOT NULL,
    completed_at  INTEGER NOT NULL,
    PRIMARY KEY (uid, date)
);

-- ---------------------------------------------------------------- misc

CREATE TABLE IF NOT EXISTS watched_media (
    uid       TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    media_key TEXT    NOT NULL,
    sources   TEXT    NOT NULL DEFAULT '["play"]',               -- JSON array: play | kinopoisk | imdb | letterboxd
    added_at  INTEGER NOT NULL,
    PRIMARY KEY (uid, media_key)
);

CREATE TABLE IF NOT EXISTS app_config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT OR IGNORE INTO app_config (key, value) VALUES
    ('curationGateEnabled',      'false'),
    ('dailyFreeAttempts',        '6'),
    ('attemptsPerCorrectStreak', '1'),
    ('curationRewardAttempts',   '1'),
    ('playlistCompletionReward', '3'),
    ('autoHideReportWeight',     '3'),
    ('catalogCacheTTLSeconds',   '86400'),
    ('voteWeightMinRounds',      '5'),
    ('targetApprovedFrames',     '12'),
    ('onboardingMediaKey',       '');
