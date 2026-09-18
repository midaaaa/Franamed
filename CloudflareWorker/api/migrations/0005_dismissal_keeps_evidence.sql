-- Dismissing complaints must not destroy them.
--
-- `dismiss-disputes` used to DELETE the reports and votes on a frame, which
-- erased exactly the rows a moderator would need to judge the person who filed
-- them. "Forty accounts reported a frame a moderator had already cleared" is a
-- signal about those accounts, and deleting it throws the signal away.
--
-- So a dismissal now marks instead of deleting: a row with `dismissed_at` set
-- no longer counts towards the frame's status, and is still there to read.

ALTER TABLE image_reports ADD COLUMN dismissed_at INTEGER;   -- NULL = still counts
ALTER TABLE image_reports ADD COLUMN dismissed_by TEXT;
ALTER TABLE image_votes   ADD COLUMN dismissed_at INTEGER;   -- NULL = still counts
ALTER TABLE image_votes   ADD COLUMN dismissed_by TEXT;

-- Every status recomputation filters on `dismissed_at IS NULL`, so the index
-- carries it rather than leaving the filter to a scan.
CREATE INDEX IF NOT EXISTS idx_reports_live ON image_reports(image_id, dismissed_at);
CREATE INDEX IF NOT EXISTS idx_votes_live   ON image_votes(image_id, dismissed_at);
