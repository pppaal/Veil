CREATE TABLE IF NOT EXISTS "user_blocks" (
  "blocker_user_id" UUID NOT NULL,
  "blocked_user_id" UUID NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_blocks_pkey" PRIMARY KEY ("blocker_user_id", "blocked_user_id"),
  CONSTRAINT "user_blocks_blocker_fkey" FOREIGN KEY ("blocker_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "user_blocks_blocked_fkey" FOREIGN KEY ("blocked_user_id") REFERENCES "users"("id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "user_blocks_blocked_user_id_idx" ON "user_blocks" ("blocked_user_id");

CREATE TABLE IF NOT EXISTS "conversation_mutes" (
  "user_id" UUID NOT NULL,
  "conversation_id" UUID NOT NULL,
  "muted_until" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "conversation_mutes_pkey" PRIMARY KEY ("user_id", "conversation_id"),
  CONSTRAINT "conversation_mutes_user_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "conversation_mutes_conversation_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "conversation_mutes_conversation_id_idx" ON "conversation_mutes" ("conversation_id");

CREATE TABLE IF NOT EXISTS "abuse_reports" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "reporter_user_id" UUID NOT NULL,
  "reported_user_id" UUID NOT NULL,
  "conversation_id" UUID,
  "message_id" UUID,
  "reason" VARCHAR(40) NOT NULL,
  "note" VARCHAR(1000),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "abuse_reports_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "abuse_reports_reporter_fkey" FOREIGN KEY ("reporter_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
  CONSTRAINT "abuse_reports_reported_fkey" FOREIGN KEY ("reported_user_id") REFERENCES "users"("id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "abuse_reports_reported_user_id_created_at_idx" ON "abuse_reports" ("reported_user_id", "created_at");
CREATE INDEX IF NOT EXISTS "abuse_reports_reporter_user_id_created_at_idx" ON "abuse_reports" ("reporter_user_id", "created_at");
