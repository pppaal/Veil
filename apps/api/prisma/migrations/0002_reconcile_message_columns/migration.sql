ALTER TABLE "messages"
  ADD COLUMN IF NOT EXISTS "client_message_id" VARCHAR(80),
  ADD COLUMN IF NOT EXISTS "conversation_order" INTEGER;

WITH ranked_messages AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (
      PARTITION BY "conversation_id"
      ORDER BY "server_received_at" ASC, "id" ASC
    ) AS "row_order"
  FROM "messages"
)
UPDATE "messages" AS target
SET
  "client_message_id" = COALESCE(target."client_message_id", CONCAT('legacy-', gen_random_uuid())),
  "conversation_order" = COALESCE(target."conversation_order", ranked_messages."row_order")
FROM ranked_messages
WHERE ranked_messages."id" = target."id";

ALTER TABLE "messages"
  ALTER COLUMN "client_message_id" SET NOT NULL,
  ALTER COLUMN "conversation_order" SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'messages_sender_device_id_client_message_id_key'
  ) THEN
    ALTER TABLE "messages"
      ADD CONSTRAINT "messages_sender_device_id_client_message_id_key"
      UNIQUE ("sender_device_id", "client_message_id");
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "messages_conversation_id_conversation_order_idx"
  ON "messages" ("conversation_id", "conversation_order");
