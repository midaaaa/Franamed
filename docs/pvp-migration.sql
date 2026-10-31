-- PvP profiles (docs/pvp.md §11). Apply after a backup:
--   wrangler d1 execute franamed --remote --file=../../docs/pvp-migration.sql
CREATE TABLE IF NOT EXISTS pvp_profiles (
    uid        TEXT PRIMARY KEY REFERENCES users(uid) ON DELETE CASCADE,
    name       TEXT,
    name_seed  INTEGER NOT NULL DEFAULT 0,
    icon       TEXT,
    color      TEXT,
    updated_at INTEGER NOT NULL
);
