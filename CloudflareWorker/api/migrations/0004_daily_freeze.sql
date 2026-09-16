-- The daily puzzle, frozen.
--
-- Frames were being chosen at request time, and the choice is deliberately
-- random inside a difficulty tier — so two people playing the same day, or one
-- person reopening it, got different frames. Storing the layout on the day is
-- what makes "the daily" a single shared puzzle, and it is also the only way a
-- substituted frame can be the same substitution for everyone.

ALTER TABLE daily_overrides ADD COLUMN frame_ids   TEXT;       -- JSON array of image ids, in order
ALTER TABLE daily_overrides ADD COLUMN spare_ids   TEXT;       -- JSON array, used when a frame 404s
ALTER TABLE daily_overrides ADD COLUMN frame_count INTEGER;
ALTER TABLE daily_overrides ADD COLUMN frozen_at   INTEGER;

-- A film must not come round twice. The check lives in the scheduling route
-- because existing rows may already repeat; this index only speeds it up.
CREATE INDEX IF NOT EXISTS idx_daily_media_key ON daily_overrides(media_key);
