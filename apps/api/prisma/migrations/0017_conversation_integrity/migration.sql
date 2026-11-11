-- Conversation integrity (wave 1).
--
-- 1. messages.envelope_version: persist the envelope format so receivers can
--    pick the right decryptor (veil-group-v1 Sender Keys, libsignal-v1, v2).
--    Rows written before this column existed were never tagged; they get the
--    original 'veil-envelope-v1' default.
ALTER TABLE "messages"
    ADD COLUMN IF NOT EXISTS "envelope_version" VARCHAR(32) NOT NULL DEFAULT 'veil-envelope-v1';

-- 2. conversations.last_order: monotonic per-conversation order counter.
--    Sends increment it under the row lock in a default-isolation
--    transaction, replacing the SERIALIZABLE MAX(conversation_order)+1 retry
--    loop, and an order is never reused after the newest message is
--    hard-deleted.
ALTER TABLE "conversations"
    ADD COLUMN IF NOT EXISTS "last_order" INTEGER NOT NULL DEFAULT 0;

-- Backfill from the highest surviving order. Orders of messages already
-- hard-deleted are unknowable here; the counter only has to move forward
-- from what still exists.
UPDATE "conversations" c
SET "last_order" = sub.max_order
FROM (
    SELECT "conversation_id", MAX("conversation_order") AS max_order
    FROM "messages"
    GROUP BY "conversation_id"
) sub
WHERE sub."conversation_id" = c."id"
  AND c."last_order" < sub.max_order;
