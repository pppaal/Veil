-- Data only, no schema change. Releases up to 0019 changed what the API
-- deletes from then on; this removes what earlier releases already left
-- behind. test/unit/backfill-migration.spec.ts runs it on a real Postgres.

-- 1. A direct conversation's direct_key is its two members' ids
--    (sortedUserIds.join('|')). Account deletion now clears it and deletes
--    direct conversations left with no members
--    (AccountService.releaseDirectConversations). Accounts deleted before that
--    left their id in the key next to the peer's. No one can open a
--    conversation with a deleted account, so such a key has nothing left to
--    dedupe. An account that still exists mid-deletion (status 'revoked') is
--    left to the retried deletion, which clears its keys itself.
UPDATE "conversations" c
   SET "direct_key" = NULL
 WHERE c."direct_key" IS NOT NULL
   AND EXISTS (
         SELECT 1
           FROM unnest(string_to_array(c."direct_key", '|')) AS key_part(user_id)
          WHERE NOT EXISTS (SELECT 1 FROM "users" u WHERE u."id"::text = key_part.user_id)
       );
DELETE FROM "conversations" c
 WHERE c."type" = 'direct'
   AND NOT EXISTS (SELECT 1 FROM "conversation_members" m WHERE m."conversation_id" = c."id");

-- 2. Leaving or being removed from a conversation now deletes the member's
--    sync cursors and mute with the membership (removeConversationMember).
--    Both are only ever written for a current member, so a row with no
--    matching membership belongs to someone who left before that.
DELETE FROM "device_conversation_states" s
 USING "devices" d
 WHERE d."id" = s."device_id"
   AND NOT EXISTS (
         SELECT 1 FROM "conversation_members" m
          WHERE m."conversation_id" = s."conversation_id" AND m."user_id" = d."user_id"
       );
DELETE FROM "conversation_mutes" mu
 WHERE NOT EXISTS (
         SELECT 1 FROM "conversation_members" m
          WHERE m."conversation_id" = mu."conversation_id" AND m."user_id" = mu."user_id"
       );
