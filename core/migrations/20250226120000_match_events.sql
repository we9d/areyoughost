BEGIN;

CREATE TABLE IF NOT EXISTS match_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid REFERENCES games(game_id) ON DELETE SET NULL,
  room_id uuid REFERENCES rooms(room_id) ON DELETE SET NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_match_events_room_created
ON match_events(room_id, created_at);

CREATE INDEX IF NOT EXISTS ix_match_events_game_created
ON match_events(game_id, created_at);

COMMIT;
