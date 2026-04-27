-- Broaden room_type compatibility for mixed environments.
-- Some deployed snapshots still use older room_type values; normalize with UPPER()
-- and allow legacy quick-play variants.

ALTER TABLE rooms
  DROP CONSTRAINT IF EXISTS rooms_room_type_check;

ALTER TABLE rooms
  ADD CONSTRAINT rooms_room_type_check
  CHECK (
    UPPER(room_type) IN (
      'PUBLIC',
      'PRIVATE',
      'MATCHMAKING',
      'QUICKPLAY',
      'QUICK_PLAY'
    )
  );

