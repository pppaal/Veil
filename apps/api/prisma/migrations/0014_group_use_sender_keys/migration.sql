-- Group Sender Keys, phase AB.2 — per-conversation opt-in flag.
-- When true the server enforces the group_epoch_stale gate on inbound group
-- sends and clients negotiate per-sender keys. Defaults false so every
-- existing group keeps the legacy single shared key with no epoch
-- enforcement. See docs/group-sender-keys-design.md.

ALTER TABLE "conversations"
    ADD COLUMN IF NOT EXISTS "group_use_sender_keys" BOOLEAN NOT NULL DEFAULT false;
