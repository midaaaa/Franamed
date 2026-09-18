-- Throwing out a whole title.
--
-- `media_items.status` could already hold 'rejected', but nothing ever wrote
-- it and `refreshMediaCounters` would have overwritten it on the next counter
-- pass. These columns are the other half: who threw the title out and why,
-- kept because "we already looked at this one and said no" is the answer to
-- the next person who imports it again.

ALTER TABLE media_items ADD COLUMN rejected_at     INTEGER;
ALTER TABLE media_items ADD COLUMN rejected_by     TEXT;
ALTER TABLE media_items ADD COLUMN rejected_reason TEXT;

-- The curation queue and the catalogue's curator filters both ask "is this
-- title out?" before anything else.
CREATE INDEX IF NOT EXISTS idx_media_status ON media_items(status);
