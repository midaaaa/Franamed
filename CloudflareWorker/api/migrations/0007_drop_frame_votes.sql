-- Players no longer vote on frames.
--
-- The swipe deck was cancelled: one player's vote made an unlocked frame
-- playable without any moderator looking at it, which is exactly what the
-- two-step curation exists to prevent. Reports stay; they live in their own
-- table and only ever hide.
--
-- Frames that votes alone had approved or rejected go back to pending, and the
-- title counters are rebuilt so the playable pool matches the new rule.

UPDATE media_images
SET status = CASE
    WHEN moderator_status IS NOT NULL THEN moderator_status
    WHEN report_weight >= COALESCE(
        (SELECT CAST(value AS REAL) FROM app_config WHERE key = 'autoHideReportWeight'), 3
    ) THEN 'rejected'
    ELSE 'pending'
END;

UPDATE media_items
SET total_images    = (SELECT COUNT(*) FROM media_images i WHERE i.media_key = media_items.key),
    reviewed_images = (SELECT COUNT(*) FROM media_images i WHERE i.media_key = media_items.key AND i.status != 'pending'),
    approved_images = (SELECT COUNT(*) FROM media_images i WHERE i.media_key = media_items.key AND i.status = 'approved');

DROP INDEX IF EXISTS idx_votes_live;
DROP TABLE IF EXISTS image_votes;

DELETE FROM app_config WHERE key IN ('curationGateEnabled', 'curationRewardAttempts');
