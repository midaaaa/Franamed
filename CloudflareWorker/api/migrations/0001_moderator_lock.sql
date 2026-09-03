-- Moderator verdicts that community voting cannot overturn.
--
-- Votes and reports keep accumulating on a locked frame; they simply stop
-- deciding its status. Keeping them is the point: "I approved this and forty
-- people have complained since" is exactly the signal a moderator needs, and
-- suppressing the reports would throw it away.

ALTER TABLE media_images ADD COLUMN moderator_status TEXT;         -- approved | rejected, NULL = not locked
ALTER TABLE media_images ADD COLUMN moderator_uid TEXT;
ALTER TABLE media_images ADD COLUMN moderator_at INTEGER;

-- Set when a moderator decides the complaints are wrong and wipes them. The
-- count survives the wipe, so a frame that has been cleared three times still
-- reads as one that keeps attracting complaints.
ALTER TABLE media_images ADD COLUMN disputes_dismissed_at INTEGER;
ALTER TABLE media_images ADD COLUMN disputes_dismissed_count INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_images_locked ON media_images(moderator_status);
