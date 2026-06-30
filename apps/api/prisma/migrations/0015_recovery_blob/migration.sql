-- Encrypted account recovery backup. Stores only the opaque, passphrase-
-- sealed client envelope (PBKDF2-SHA256 600k + AES-256-GCM); the passphrase
-- and derived key never reach the server, so the server cannot decrypt this.
-- One row per user (PK = user_id); re-uploading replaces the prior backup.
-- See docs/recovery-backup-design.md.

CREATE TABLE IF NOT EXISTS "recovery_blobs" (
    "user_id" UUID NOT NULL,
    "ciphertext" TEXT NOT NULL,
    "format" VARCHAR(32) NOT NULL DEFAULT 'veilbak:v1',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "recovery_blobs_pkey" PRIMARY KEY ("user_id"),
    CONSTRAINT "recovery_blobs_user_id_fkey"
        FOREIGN KEY ("user_id") REFERENCES "users" ("id")
        ON DELETE CASCADE ON UPDATE CASCADE
);
