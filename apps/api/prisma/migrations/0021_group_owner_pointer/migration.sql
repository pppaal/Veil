-- Data only, no schema change. group_metas.created_by_user_id is the group's
-- current-owner pointer: account deletion deletes the groups it names, and
-- ownership transfer now moves it with the owner role
-- (GroupsService.transferOwnership). Earlier releases left it naming the
-- creator after a transfer, so deleting a former owner's account deleted a
-- group someone else owned, and deleting the current owner's left the group
-- with no owner. This points every group at its current owner.
-- test/unit/backfill-migration.spec.ts runs it on a real Postgres.
UPDATE "group_metas" gm
   SET "created_by_user_id" = o."user_id"
  FROM (
         SELECT DISTINCT ON ("conversation_id") "conversation_id", "user_id"
           FROM "conversation_members"
          WHERE "role" = 'owner'
          ORDER BY "conversation_id", "joined_at", "user_id"
       ) o
 WHERE o."conversation_id" = gm."conversation_id"
   AND gm."created_by_user_id" <> o."user_id";
