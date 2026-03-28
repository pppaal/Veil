CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE "UserStatus" AS ENUM ('active', 'locked', 'revoked');
CREATE TYPE "DevicePlatform" AS ENUM ('ios', 'android');
CREATE TYPE "ConversationType" AS ENUM ('direct');
CREATE TYPE "MessageType" AS ENUM ('text', 'image', 'file', 'system');
CREATE TYPE "AttachmentUploadStatus" AS ENUM ('pending', 'uploaded', 'failed');

CREATE TABLE "users" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "handle" VARCHAR(32) NOT NULL UNIQUE,
  "display_name" VARCHAR(80),
  "avatar_path" TEXT,
  "status" "UserStatus" NOT NULL DEFAULT 'active',
  "active_device_id" UUID,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "devices" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "platform" "DevicePlatform" NOT NULL,
  "device_name" VARCHAR(80) NOT NULL,
  "public_identity_key" TEXT NOT NULL,
  "signed_prekey_bundle" TEXT NOT NULL,
  "auth_public_key" TEXT NOT NULL,
  "push_token" TEXT,
  "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
  "revoked_at" TIMESTAMPTZ,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "last_seen_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "conversations" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "type" "ConversationType" NOT NULL DEFAULT 'direct',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "conversation_members" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "conversation_id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "joined_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "conversation_members_conversation_id_user_id_key" UNIQUE ("conversation_id", "user_id")
);

CREATE TABLE "attachments" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "uploader_device_id" UUID NOT NULL,
  "storage_key" TEXT NOT NULL,
  "content_type" TEXT NOT NULL,
  "size_bytes" INTEGER NOT NULL,
  "sha256" TEXT NOT NULL,
  "upload_status" "AttachmentUploadStatus" NOT NULL DEFAULT 'pending',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE "messages" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "conversation_id" UUID NOT NULL,
  "sender_device_id" UUID NOT NULL,
  "ciphertext" TEXT NOT NULL,
  "nonce" TEXT NOT NULL,
  "message_type" "MessageType" NOT NULL,
  "attachment_id" UUID,
  "attachment_ref" JSONB,
  "server_received_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "deleted_at" TIMESTAMPTZ,
  "expires_at" TIMESTAMPTZ
);

CREATE TABLE "message_receipts" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "message_id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "delivered_at" TIMESTAMPTZ,
  "read_at" TIMESTAMPTZ,
  CONSTRAINT "message_receipts_message_id_user_id_key" UNIQUE ("message_id", "user_id")
);

CREATE TABLE "device_transfer_sessions" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "old_device_id" UUID NOT NULL,
  "token_hash" TEXT NOT NULL,
  "expires_at" TIMESTAMPTZ NOT NULL,
  "completed_at" TIMESTAMPTZ,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX "users_active_device_id_idx" ON "users" ("active_device_id");
CREATE INDEX "devices_user_id_is_active_idx" ON "devices" ("user_id", "is_active");
CREATE INDEX "conversation_members_user_id_idx" ON "conversation_members" ("user_id");
CREATE INDEX "messages_conversation_id_server_received_at_idx" ON "messages" ("conversation_id", "server_received_at");
CREATE INDEX "messages_attachment_id_idx" ON "messages" ("attachment_id");
CREATE INDEX "message_receipts_user_id_idx" ON "message_receipts" ("user_id");
CREATE INDEX "attachments_uploader_device_id_created_at_idx" ON "attachments" ("uploader_device_id", "created_at");
CREATE INDEX "attachments_storage_key_idx" ON "attachments" ("storage_key");
CREATE INDEX "device_transfer_sessions_user_id_expires_at_idx" ON "device_transfer_sessions" ("user_id", "expires_at");
CREATE INDEX "device_transfer_sessions_old_device_id_idx" ON "device_transfer_sessions" ("old_device_id");

ALTER TABLE "devices"
  ADD CONSTRAINT "devices_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "users"
  ADD CONSTRAINT "users_active_device_id_fkey"
  FOREIGN KEY ("active_device_id") REFERENCES "devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "conversation_members"
  ADD CONSTRAINT "conversation_members_conversation_id_fkey"
  FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "conversation_members"
  ADD CONSTRAINT "conversation_members_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "attachments"
  ADD CONSTRAINT "attachments_uploader_device_id_fkey"
  FOREIGN KEY ("uploader_device_id") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "messages"
  ADD CONSTRAINT "messages_conversation_id_fkey"
  FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "messages"
  ADD CONSTRAINT "messages_sender_device_id_fkey"
  FOREIGN KEY ("sender_device_id") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "messages"
  ADD CONSTRAINT "messages_attachment_id_fkey"
  FOREIGN KEY ("attachment_id") REFERENCES "attachments"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "message_receipts"
  ADD CONSTRAINT "message_receipts_message_id_fkey"
  FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "message_receipts"
  ADD CONSTRAINT "message_receipts_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "device_transfer_sessions"
  ADD CONSTRAINT "device_transfer_sessions_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "device_transfer_sessions"
  ADD CONSTRAINT "device_transfer_sessions_old_device_id_fkey"
  FOREIGN KEY ("old_device_id") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
