-- Group Sender Keys, phase AB.1 — server-side epoch bookkeeping.
-- current_epoch is a monotonic per-conversation counter bumped on every
-- group membership change. group_member_epochs records, per member, the
-- epoch they were allowed to start decrypting (joined_epoch) and the epoch
-- they left/were removed (left_epoch). No key material is stored here; key
-- distribution rides the existing 1:1 ratchet. See
-- docs/group-sender-keys-design.md.

ALTER TABLE "conversations"
    ADD COLUMN IF NOT EXISTS "current_epoch" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS "group_member_epochs" (
    "conversation_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "joined_epoch" INTEGER NOT NULL,
    "left_epoch" INTEGER,
    CONSTRAINT "group_member_epochs_pkey" PRIMARY KEY ("conversation_id", "user_id"),
    CONSTRAINT "group_member_epochs_conversation_id_fkey"
        FOREIGN KEY ("conversation_id") REFERENCES "conversations" ("id")
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "group_member_epochs_user_id_fkey"
        FOREIGN KEY ("user_id") REFERENCES "users" ("id")
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "group_member_epochs_user_id_idx"
    ON "group_member_epochs" ("user_id");
