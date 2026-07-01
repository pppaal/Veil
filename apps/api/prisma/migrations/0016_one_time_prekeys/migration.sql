-- X3DH one-time prekeys (OPKs). A per-device pool of single-use public
-- prekeys. The server stores only the public key; the private half never
-- leaves the device. A session initiator atomically claims one unused OPK
-- (consumed_at set, never handed out twice); empty pool falls back to
-- signed-prekey-only X3DH. See docs/libsignal-migration-design.md (L.4).

CREATE TABLE IF NOT EXISTS "one_time_prekeys" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "device_id" UUID NOT NULL,
    "key_id" INTEGER NOT NULL,
    "public_key" TEXT NOT NULL,
    "consumed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "one_time_prekeys_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "one_time_prekeys_device_id_fkey"
        FOREIGN KEY ("device_id") REFERENCES "devices" ("id")
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "one_time_prekeys_device_id_key_id_key"
    ON "one_time_prekeys" ("device_id", "key_id");

CREATE INDEX IF NOT EXISTS "one_time_prekeys_device_id_consumed_at_idx"
    ON "one_time_prekeys" ("device_id", "consumed_at");
