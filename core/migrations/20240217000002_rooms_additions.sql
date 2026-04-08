-- Migration: rooms and room_members table additions
-- Adds lobby_start_time to rooms for Quick Play 120s lobby timer tracking

BEGIN;

ALTER TABLE rooms
  ADD COLUMN IF NOT EXISTS lobby_start_time timestamptz;

COMMIT;
