-- One-time secret links. Stores only client-side ciphertext; the key
-- never reaches the server. Rows are hard-deleted on first read
-- (burn-after-read) and swept after expires_at.
CREATE TABLE IF NOT EXISTS "secret_blobs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "ciphertext" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "secret_blobs_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "secret_blobs_expires_at_idx"
    ON "secret_blobs" ("expires_at");
