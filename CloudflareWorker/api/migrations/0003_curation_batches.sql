-- A curator's work as a proposal.
--
-- Nothing here is applied on its own: a batch is reviewed by a moderator, who
-- edits it and applies it, or rejects it. That is why there is no staging copy
-- of the frames — the existing `pending` status already means "proposed", and
-- the proposal itself is just this row.
--
-- The id is the client's idempotency key: a submission that succeeds on the
-- server but loses its response must not turn into a second batch on retry.

CREATE TABLE IF NOT EXISTS curation_batches (
    id                  TEXT PRIMARY KEY,                      -- client-generated UUID
    media_key           TEXT    NOT NULL REFERENCES media_items(key) ON DELETE CASCADE,
    uid                 TEXT    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    state               TEXT    NOT NULL DEFAULT 'pending',    -- pending | applied | rejected
    verdicts            TEXT    NOT NULL,                      -- JSON [{imageId,status,difficultyTier}]
    reject_remaining    INTEGER NOT NULL DEFAULT 0,
    note                TEXT,
    submitted_at        INTEGER NOT NULL,

    reviewed_by         TEXT,
    reviewed_at         INTEGER,
    review_outcome      TEXT,                                  -- applied | rejected_neutral | rejected_poor
    review_note         TEXT,

    -- How much the reviewer had to change. Overturned approvals are the honest
    -- measure of a curator's accuracy: picking a different good frame is not a
    -- mistake, picking one the reviewer throws out is.
    edits_count         INTEGER,
    overturned_approvals INTEGER
);

CREATE INDEX IF NOT EXISTS idx_batches_state ON curation_batches(state, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_batches_uid   ON curation_batches(uid, submitted_at DESC);

-- One open proposal per title. A second one would have been built on a state
-- the first is about to change.
CREATE UNIQUE INDEX IF NOT EXISTS idx_batches_open_title
    ON curation_batches(media_key) WHERE state = 'pending';
