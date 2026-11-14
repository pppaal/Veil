-- Metadata minimisation. Each step removes metadata the server kept without
-- needing it; none of it can be rebuilt afterwards.

-- 1. device_conversation_states.updated_at recorded the exact moment a device
--    last fetched, sent in or read each conversation, for the account's
--    lifetime, and nothing read it. Drop it and its indexes; a plain
--    conversation_id index serves the cascade from conversations (the unique
--    index already covers lookups by device_id).
DROP INDEX IF EXISTS "device_conversation_states_device_id_updated_at_idx";
DROP INDEX IF EXISTS "device_conversation_states_conversation_id_updated_at_idx";
ALTER TABLE "device_conversation_states" DROP COLUMN IF EXISTS "updated_at";
CREATE INDEX IF NOT EXISTS "device_conversation_states_conversation_id_idx"
    ON "device_conversation_states" ("conversation_id");

-- 2. group_member_epochs keeps current members only: a member's row is now
--    deleted when they leave or are removed. Former members' rows go now, and
--    so does left_epoch, which nothing read.
DELETE FROM "group_member_epochs" WHERE "left_epoch" IS NOT NULL;
ALTER TABLE "group_member_epochs" DROP COLUMN IF EXISTS "left_epoch";

-- 3. A revoked device now loses its label, one-time prekeys and sync cursors
--    when it is revoked, and RetentionService (revokedDevices) deletes the row
--    30 days later once nothing references it. Devices revoked before this
--    release get the same treatment; the sweep then removes their rows.
UPDATE "devices" SET "device_name" = 'Removed device' WHERE "revoked_at" IS NOT NULL;
DELETE FROM "one_time_prekeys"
    WHERE "device_id" IN (SELECT "id" FROM "devices" WHERE "revoked_at" IS NOT NULL);
DELETE FROM "device_conversation_states"
    WHERE "device_id" IN (SELECT "id" FROM "devices" WHERE "revoked_at" IS NOT NULL);
CREATE INDEX IF NOT EXISTS "devices_revoked_at_idx" ON "devices" ("revoked_at");
