ALTER TABLE "devices"
  ADD COLUMN IF NOT EXISTS "trusted_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS "joined_from_device_id" UUID,
  ADD COLUMN IF NOT EXISTS "last_sync_at" TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'devices_joined_from_device_id_fkey'
  ) THEN
    ALTER TABLE "devices"
      ADD CONSTRAINT "devices_joined_from_device_id_fkey"
      FOREIGN KEY ("joined_from_device_id") REFERENCES "devices"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "devices_joined_from_device_id_idx"
  ON "devices" ("joined_from_device_id");

CREATE TABLE IF NOT EXISTS "device_conversation_states" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "device_id" UUID NOT NULL,
  "conversation_id" UUID NOT NULL,
  "last_synced_conversation_order" INTEGER,
  "last_read_conversation_order" INTEGER,
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT "device_conversation_states_device_id_conversation_id_key"
    UNIQUE ("device_id", "conversation_id")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'device_conversation_states_device_id_fkey'
  ) THEN
    ALTER TABLE "device_conversation_states"
      ADD CONSTRAINT "device_conversation_states_device_id_fkey"
      FOREIGN KEY ("device_id") REFERENCES "devices"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'device_conversation_states_conversation_id_fkey'
  ) THEN
    ALTER TABLE "device_conversation_states"
      ADD CONSTRAINT "device_conversation_states_conversation_id_fkey"
      FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "device_conversation_states_device_id_updated_at_idx"
  ON "device_conversation_states" ("device_id", "updated_at");

CREATE INDEX IF NOT EXISTS "device_conversation_states_conversation_id_updated_at_idx"
  ON "device_conversation_states" ("conversation_id", "updated_at");
