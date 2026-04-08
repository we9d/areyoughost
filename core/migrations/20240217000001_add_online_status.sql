BEGIN;

ALTER TABLE players
  ADD COLUMN IF NOT EXISTS online_status text NOT NULL DEFAULT 'offline'
    CHECK (online_status IN ('online', 'offline'));

COMMIT;
