ALTER TABLE "conversations"
  ADD COLUMN IF NOT EXISTS "disappearing_timer_seconds" INTEGER;
