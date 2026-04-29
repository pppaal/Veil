-- Adds reply/edit metadata to messages. Soft-delete already exists via
-- deleted_at — we only add reply_to_message_id, edited_at, edit_count.

-- Reply target. Nullable because most messages aren't replies. ON DELETE
-- SET NULL: when the original message is deleted, the reply chip survives
-- but the link goes dead — the UI is expected to show "원본 삭제됨".
ALTER TABLE "messages" ADD COLUMN IF NOT EXISTS "reply_to_message_id" UUID;
ALTER TABLE "messages" ADD COLUMN IF NOT EXISTS "edited_at" TIMESTAMP(3);
ALTER TABLE "messages" ADD COLUMN IF NOT EXISTS "edit_count" INTEGER NOT NULL DEFAULT 0;

-- Foreign key. DO block keeps it idempotent if the constraint already
-- exists from a prior partial run.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'messages_reply_to_message_id_fkey'
  ) THEN
    ALTER TABLE "messages"
      ADD CONSTRAINT "messages_reply_to_message_id_fkey"
      FOREIGN KEY ("reply_to_message_id") REFERENCES "messages"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

-- Index on reply_to_message_id so "show all replies to this thread"
-- stays cheap even if a particular message gets a viral reply chain.
CREATE INDEX IF NOT EXISTS "messages_reply_to_message_id_idx"
  ON "messages" ("reply_to_message_id");
