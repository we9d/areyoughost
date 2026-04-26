BEGIN;

-- Align schema with server auth/register flow.
ALTER TABLE players
  ADD COLUMN IF NOT EXISTS email text;

-- Keep compatibility with existing error handling that references this name.
CREATE UNIQUE INDEX IF NOT EXISTS players_email_key
  ON players(email)
  WHERE email IS NOT NULL;

-- Align schema with room creation flow in manager.rs.
ALTER TABLE rooms
  ADD COLUMN IF NOT EXISTS room_type text;

UPDATE rooms
SET room_type = CASE
  WHEN is_public THEN 'PUBLIC'
  ELSE 'PRIVATE'
END
WHERE room_type IS NULL;

ALTER TABLE rooms
  ALTER COLUMN room_type SET DEFAULT 'PUBLIC';

ALTER TABLE rooms
  ALTER COLUMN room_type SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'rooms_room_type_check'
  ) THEN
    ALTER TABLE rooms
      ADD CONSTRAINT rooms_room_type_check
      CHECK (room_type IN ('PUBLIC', 'PRIVATE', 'MATCHMAKING'));
  END IF;
END $$;

-- Speed up member list queries:
--   WHERE room_id = $1 AND member_status = 'JOINED' ORDER BY joined_at ASC
CREATE INDEX IF NOT EXISTS ix_room_members_room_status_joined
  ON room_members(room_id, member_status, joined_at);

COMMIT;

