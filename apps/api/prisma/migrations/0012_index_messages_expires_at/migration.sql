-- The disappearing-message sweep filters messages on expires_at every ~10
-- minutes. Without an index this full-scans the largest table and gets
-- slower forever. Matches @@index([expiresAt]) on the Message model.
CREATE INDEX IF NOT EXISTS "messages_expires_at_idx"
    ON "messages" ("expires_at");
