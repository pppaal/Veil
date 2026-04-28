-- Drop the non-unique index that's about to be replaced by a UNIQUE index
-- of the same shape. IF EXISTS keeps the migration idempotent.
DROP INDEX IF EXISTS "messages_conversation_id_conversation_order_idx";

-- Direct-conversation dedupe key. Populated by the application as
-- sortedUserIds.join('|') for direct rows; left null for group/channel.
ALTER TABLE "conversations" ADD COLUMN IF NOT EXISTS "direct_key" VARCHAR(80);

-- Backfill: compute direct_key for any existing direct conversations from
-- their two members so the migration also helps existing deployments.
UPDATE "conversations" c SET "direct_key" = sub.key
FROM (
  SELECT cm."conversation_id" AS conversation_id,
         string_agg(cm."user_id"::text, '|' ORDER BY cm."user_id"::text) AS key
  FROM "conversation_members" cm
  JOIN "conversations" c2 ON c2."id" = cm."conversation_id"
  WHERE c2."type" = 'direct'
  GROUP BY cm."conversation_id"
  HAVING COUNT(*) = 2
) sub
WHERE sub.conversation_id = c."id" AND c."direct_key" IS NULL;

-- Unique index that defeats the createDirect TOCTOU race. Two concurrent
-- inserts between the same pair both try to write the same direct_key;
-- exactly one wins, the other gets P2002 and the service returns the
-- existing conversation.
CREATE UNIQUE INDEX IF NOT EXISTS "conversations_direct_key_key"
  ON "conversations"("direct_key");

-- Hard guarantee no duplicate (conversation, order). Together with the
-- application's existing SERIALIZABLE retry, this means the order column
-- has no gaps and no duplicates even if isolation is later weakened.
CREATE UNIQUE INDEX IF NOT EXISTS "messages_conversation_id_conversation_order_key"
  ON "messages"("conversation_id", "conversation_order");
