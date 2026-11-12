-- Data only, no schema change. Releases up to 0019 changed what the API
-- deletes from then on; this removes what earlier releases already left
-- behind. test/unit/backfill-migration.spec.ts runs it on a real Postgres.

-- 1. A direct conversation's direct_key is its two members' ids
--    (sortedUserIds.join('|')), so createDirect finds the pair's
--    conversation. Account deletion now clears it and deletes direct
--    conversations left with no members
--    (AccountService.releaseDirectConversations). Earlier releases left keys
--    naming someone who is no longer a member of the conversation:
--    - accounts deleted before that change: the user row went, its
--      memberships cascaded, and the key kept its id;
--    - accounts whose deletion failed before that change: Phase 2 had
--      deleted every membership, direct ones included, and the user row
--      stays with status 'revoked', so a retry finds no direct conversation
--      through the memberships;
--    - members who left a direct conversation through the group-leave or
--      channel-unsubscribe routes, which did not check the conversation type
--      before the conversation-integrity release.
--    Such a key dedupes nothing (createDirect would hand back a conversation
--    one of the pair is not in), so it is cleared. Today only account
--    deletion removes a direct membership, and it keeps them until the
--    transaction that clears the key, so a deletion in progress, whose
--    memberships are still there, is left to its retry. The lookup goes
--    through the conversation_members (conversation_id, user_id) index, not a
--    scan of users.
UPDATE "conversations" c
   SET "direct_key" = NULL
 WHERE c."direct_key" IS NOT NULL
   AND EXISTS (
         SELECT 1
           FROM unnest(string_to_array(c."direct_key", '|')) AS key_part(user_id)
          WHERE NOT EXISTS (
                  SELECT 1
                    FROM "conversation_members" m
                   WHERE m."conversation_id" = c."id"
                     AND m."user_id"::text = key_part.user_id
                )
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
