-- Migration: game tables additions
-- Adds day_number to chat_messages for night history keying by day
-- Required by ChatSystem.get_day_history() and get_night_history()

BEGIN;

ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS day_number int NOT NULL DEFAULT 1;

COMMIT;
