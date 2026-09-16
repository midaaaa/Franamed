-- One person at a time on a title.
--
-- A curator's work is entirely local — taps on thumbnails, images fetched
-- straight from TMDB — so the server sees no activity at all unless the client
-- says so. Hence touched_at and a heartbeat: without it a lease would expire
-- under someone who never left the screen.
--
-- Rows are kept after release so the next acquire reuses them; the primary key
-- is the title, not the lease, because only one can be live at a time.

CREATE TABLE IF NOT EXISTS title_leases (
    media_key   TEXT PRIMARY KEY REFERENCES media_items(key) ON DELETE CASCADE,
    uid         TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    role        TEXT    NOT NULL,                              -- role held when the lease was taken
    acquired_at INTEGER NOT NULL,
    touched_at  INTEGER NOT NULL,                              -- expiry is touched_at + the window
    released_at INTEGER                                        -- NULL = live
);
CREATE INDEX IF NOT EXISTS idx_leases_live ON title_leases(released_at, touched_at);
CREATE INDEX IF NOT EXISTS idx_leases_uid  ON title_leases(uid);

-- A curator who loses a title mid-work is told why by name. Someone who
-- silently loses twenty minutes of work does not come back a second time.
CREATE TABLE IF NOT EXISTS lease_notices (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    uid          TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    media_key    TEXT    NOT NULL,
    taken_by     TEXT    NOT NULL,
    taken_role   TEXT    NOT NULL,
    reason       TEXT,
    created_at   INTEGER NOT NULL,
    delivered_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_lease_notices_uid ON lease_notices(uid, delivered_at);
