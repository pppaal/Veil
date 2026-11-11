-- Plaintext elimination (wave 2). After this migration the server stores no
-- plaintext user content: every remaining user-written field is ciphertext,
-- except the group/channel name and description allowlisted in
-- scripts/schema-privacy-check.mjs.

-- 1. Reactions travel as end-to-end encrypted messages (messageType
--    'reaction'); the plaintext emoji table goes.
DROP TABLE IF EXISTS "reactions";

-- 2. Profiles: display name, avatar, bio and status are not stored until they
--    can be stored end-to-end encrypted.
DROP TABLE IF EXISTS "user_profiles";
ALTER TABLE "users"
    DROP COLUMN IF EXISTS "display_name",
    DROP COLUMN IF EXISTS "avatar_path";
ALTER TABLE "group_metas" DROP COLUMN IF EXISTS "avatar_path";
ALTER TABLE "channel_metas" DROP COLUMN IF EXISTS "avatar_path";

-- 3. Contact nicknames stay on the device; report notes had no reader.
ALTER TABLE "user_contacts" DROP COLUMN IF EXISTS "nickname";
ALTER TABLE "abuse_reports" DROP COLUMN IF EXISTS "note";

-- 4. No backup, no recovery: the passphrase-sealed identity store goes.
DROP TABLE IF EXISTS "recovery_blobs";

-- 5. Stories become ciphertext for an explicit audience. Existing plaintext
--    stories cannot be converted and live at most 24 hours anyway, so they
--    are deleted (their views cascade). view_count was never written: the
--    author's view count is counted from story_views.
DELETE FROM "stories";
ALTER TABLE "stories"
    DROP COLUMN IF EXISTS "content_type",
    DROP COLUMN IF EXISTS "content_url",
    DROP COLUMN IF EXISTS "caption",
    DROP COLUMN IF EXISTS "view_count",
    ADD COLUMN "ciphertext" TEXT NOT NULL,
    ADD COLUMN "envelope_version" VARCHAR(32) NOT NULL;
DROP TYPE IF EXISTS "StoryContentType";

CREATE TABLE "story_audiences" (
    "story_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    CONSTRAINT "story_audiences_pkey" PRIMARY KEY ("story_id", "user_id"),
    CONSTRAINT "story_audiences_story_id_fkey"
        FOREIGN KEY ("story_id") REFERENCES "stories" ("id")
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "story_audiences_user_id_fkey"
        FOREIGN KEY ("user_id") REFERENCES "users" ("id")
        ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "story_audiences_user_id_idx" ON "story_audiences" ("user_id");

-- 6. Handle quarantine: a deleted account's handle cannot be re-registered
--    until retired_until. Only HMAC-SHA256(pepper, lowercase handle) is kept.
CREATE TABLE "retired_handles" (
    "handle_hmac" VARCHAR(64) NOT NULL,
    "retired_until" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "retired_handles_pkey" PRIMARY KEY ("handle_hmac")
);
CREATE INDEX "retired_handles_retired_until_idx" ON "retired_handles" ("retired_until");

-- 7. Activity timestamps keep the UTC day only. Timestamps are stored as UTC
--    TIMESTAMP(3), so truncating to the day yields the UTC day start.
UPDATE "devices"
SET "last_seen_at" = date_trunc('day', "last_seen_at"),
    "last_sync_at" = date_trunc('day', "last_sync_at");

-- 8. Indexes the retention sweeps filter on, so each 10-minute tick does not
--    full-scan these tables.
CREATE INDEX IF NOT EXISTS "messages_server_received_at_idx" ON "messages" ("server_received_at");
CREATE INDEX IF NOT EXISTS "message_receipts_read_at_idx" ON "message_receipts" ("read_at");
CREATE INDEX IF NOT EXISTS "message_receipts_delivered_at_idx" ON "message_receipts" ("delivered_at");
CREATE INDEX IF NOT EXISTS "abuse_reports_created_at_idx" ON "abuse_reports" ("created_at");
CREATE INDEX IF NOT EXISTS "call_records_status_started_at_idx" ON "call_records" ("status", "started_at");
CREATE INDEX IF NOT EXISTS "attachments_created_at_idx" ON "attachments" ("created_at");
