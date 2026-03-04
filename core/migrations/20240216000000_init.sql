BEGIN;

-- UUID generator (Supabase มักเปิด pgcrypto ไว้แล้ว แต่ใส่ไว้ให้ชัวร์)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Auto-updated updated_at trigger
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =========================
-- 1) PLAYERS
-- =========================
CREATE TABLE IF NOT EXISTS players (
  player_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username      text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  last_login    timestamptz,
  CONSTRAINT username_len CHECK (length(username) BETWEEN 3 AND 20)
);

DROP TRIGGER IF EXISTS trg_players_updated_at ON players;
CREATE TRIGGER trg_players_updated_at
BEFORE UPDATE ON players
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================
-- 2) PLAYER_SESSIONS
-- =========================
CREATE TABLE IF NOT EXISTS player_sessions (
  session_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id            uuid NOT NULL,
  refresh_token_hash   text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  expires_at           timestamptz NOT NULL,
  revoked_at           timestamptz,
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_player_sessions_player
ON player_sessions(player_id);

CREATE INDEX IF NOT EXISTS ix_player_sessions_expires
ON player_sessions(expires_at);

-- =========================
-- 3) FRIENDSHIPS
-- =========================
CREATE TABLE IF NOT EXISTS friendships (
  friendship_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id   uuid NOT NULL,
  addressee_id   uuid NOT NULL,
  status         text NOT NULL CHECK (status IN ('PENDING','ACCEPTED','BLOCKED')),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (requester_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (addressee_id) REFERENCES players(player_id) ON DELETE CASCADE,
  CHECK (requester_id <> addressee_id)
);

DROP TRIGGER IF EXISTS trg_friendships_updated_at ON friendships;
CREATE TRIGGER trg_friendships_updated_at
BEFORE UPDATE ON friendships
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Unique pair (กันซ้ำ request->addressee)
CREATE UNIQUE INDEX IF NOT EXISTS ux_friendships_pair
ON friendships(requester_id, addressee_id);

CREATE INDEX IF NOT EXISTS ix_friendships_requester
ON friendships(requester_id);

CREATE INDEX IF NOT EXISTS ix_friendships_addressee
ON friendships(addressee_id);

-- =========================
-- 4) ROOMS
-- =========================
CREATE TABLE IF NOT EXISTS rooms (
  room_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id      uuid NOT NULL,
  room_name     text NOT NULL,
  max_players   int NOT NULL CHECK (max_players BETWEEN 1 AND 16),
  is_public     boolean NOT NULL DEFAULT true,
  room_status   text NOT NULL CHECK (room_status IN ('WAITING','PLAYING','CLOSED')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (owner_id) REFERENCES players(player_id) ON DELETE CASCADE
);

DROP TRIGGER IF EXISTS trg_rooms_updated_at ON rooms;
CREATE TRIGGER trg_rooms_updated_at
BEFORE UPDATE ON rooms
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS ix_rooms_owner
ON rooms(owner_id);

CREATE INDEX IF NOT EXISTS ix_rooms_public_status
ON rooms(is_public, room_status);

-- =========================
-- 5) ROOM_MEMBERS
-- =========================
CREATE TABLE IF NOT EXISTS room_members (
  room_member_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id         uuid NOT NULL,
  player_id       uuid NOT NULL,
  member_status   text NOT NULL CHECK (member_status IN ('JOINED','LEFT','KICKED','LOST')),
  joined_at       timestamptz NOT NULL DEFAULT now(),
  left_at         timestamptz,
  lost_at         timestamptz,
  FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE,
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_room_members_room_player
ON room_members(room_id, player_id);

CREATE INDEX IF NOT EXISTS ix_room_members_room
ON room_members(room_id);

CREATE INDEX IF NOT EXISTS ix_room_members_player
ON room_members(player_id);

-- =========================
-- 6) ROOM_INVITES
-- =========================
CREATE TABLE IF NOT EXISTS room_invites (
  invite_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id       uuid NOT NULL,
  inviter_id    uuid NOT NULL,
  invitee_id    uuid NOT NULL,
  status        text NOT NULL CHECK (status IN ('PENDING','ACCEPTED','DECLINED','CANCELED')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  responded_at  timestamptz,
  FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE,
  FOREIGN KEY (inviter_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (invitee_id) REFERENCES players(player_id) ON DELETE CASCADE,
  CHECK (inviter_id <> invitee_id)
);

CREATE INDEX IF NOT EXISTS ix_room_invites_room
ON room_invites(room_id);

CREATE INDEX IF NOT EXISTS ix_room_invites_invitee
ON room_invites(invitee_id);

-- =========================
-- 7) ROLES
-- =========================
CREATE TABLE IF NOT EXISTS roles (
  role_id      integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  role_code    text NOT NULL UNIQUE,
  role_name    text NOT NULL,
  faction      text NOT NULL CHECK (faction IN ('VILLAGER','GHOST','SPECIAL')),
  description  text,
  skill_1      text,
  skill_2      text
);

-- =========================
-- 8) GAMES
-- =========================
CREATE TABLE IF NOT EXISTS games (
  game_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id        uuid NOT NULL,
  started_at     timestamptz NOT NULL DEFAULT now(),
  ended_at       timestamptz,
  game_status    text NOT NULL CHECK (game_status IN ('ONGOING','FINISHED')),
  winner_faction text,
  random_seed    bigint NOT NULL,
  FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_games_room
ON games(room_id);

CREATE INDEX IF NOT EXISTS ix_games_status
ON games(game_status);

-- =========================
-- 9) GAME_PARTICIPANTS
-- =========================
CREATE TABLE IF NOT EXISTS game_participants (
  game_participant_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id              uuid NOT NULL,
  player_id            uuid NOT NULL,
  role_id              integer NOT NULL,
  is_alive             boolean NOT NULL DEFAULT true,
  seat_number          int NOT NULL,
  joined_at            timestamptz NOT NULL DEFAULT now(),
  died_at              timestamptz,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (role_id) REFERENCES roles(role_id),
  UNIQUE (game_id, player_id),
  UNIQUE (game_id, seat_number)
);

CREATE INDEX IF NOT EXISTS ix_game_participants_game
ON game_participants(game_id);

CREATE INDEX IF NOT EXISTS ix_game_participants_player
ON game_participants(player_id);

-- =========================
-- 10) GAME_PHASES
-- =========================
CREATE TABLE IF NOT EXISTS game_phases (
  phase_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id      uuid NOT NULL,
  phase_type   text NOT NULL CHECK (phase_type IN ('NIGHT','DAY','VOTE')),
  vote_scope   text CHECK (vote_scope IN ('DAY','GHOST')),
  phase_order  int NOT NULL,
  started_at   timestamptz NOT NULL DEFAULT now(),
  ended_at     timestamptz,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  UNIQUE (game_id, phase_order),
  CHECK (
    (phase_type = 'VOTE' AND vote_scope IS NOT NULL)
    OR
    (phase_type <> 'VOTE')
  )
);

CREATE INDEX IF NOT EXISTS ix_game_phases_game
ON game_phases(game_id);

-- =========================
-- 11) GAME_ACTIONS
-- =========================
CREATE TABLE IF NOT EXISTS game_actions (
  action_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id        uuid NOT NULL,
  phase_id       uuid NOT NULL,
  actor_id       uuid NOT NULL,
  target_id      uuid,
  action_type    text NOT NULL,
  action_payload jsonb,
  created_at     timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id),
  FOREIGN KEY (actor_id) REFERENCES game_participants(game_participant_id),
  FOREIGN KEY (target_id) REFERENCES game_participants(game_participant_id)
);

CREATE INDEX IF NOT EXISTS ix_game_actions_game
ON game_actions(game_id);

CREATE INDEX IF NOT EXISTS ix_game_actions_phase
ON game_actions(phase_id);

-- =========================
-- 12) VOTES
-- =========================
CREATE TABLE IF NOT EXISTS votes (
  vote_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id      uuid NOT NULL,
  phase_id     uuid NOT NULL,
  voter_id     uuid NOT NULL,
  candidate_id uuid, -- NULL = Skip Vote
  created_at   timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id),
  FOREIGN KEY (voter_id) REFERENCES game_participants(game_participant_id),
  FOREIGN KEY (candidate_id) REFERENCES game_participants(game_participant_id),
  UNIQUE (phase_id, voter_id)
);

CREATE INDEX IF NOT EXISTS ix_votes_phase
ON votes(phase_id);

-- =========================
-- 13) CHAT_MESSAGES
-- =========================
CREATE TABLE IF NOT EXISTS chat_messages (
  message_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id      uuid NOT NULL,
  phase_id     uuid,
  sender_id    uuid NOT NULL,
  chat_scope   text NOT NULL CHECK (chat_scope IN ('PUBLIC','GHOST','SYSTEM')),
  message_text text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id),
  FOREIGN KEY (sender_id) REFERENCES players(player_id)
);

CREATE INDEX IF NOT EXISTS ix_chat_messages_game
ON chat_messages(game_id);

CREATE INDEX IF NOT EXISTS ix_chat_messages_created
ON chat_messages(created_at);

-- =========================
-- 14) GAME_RESULTS
-- =========================
CREATE TABLE IF NOT EXISTS game_results (
  result_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id          uuid NOT NULL UNIQUE,
  winner_faction   text NOT NULL,
  duration_seconds int NOT NULL,
  total_turns      int NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE
);

-- =========================
-- 15) NETWORK_LOGS
-- =========================
CREATE TABLE IF NOT EXISTS network_logs (
  log_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id    uuid,
  session_id uuid,
  direction  text NOT NULL CHECK (direction IN ('IN','OUT')),
  msg_type   text NOT NULL,
  bytes      int NOT NULL,
  dropped    int NOT NULL DEFAULT 0,
  latency_ms int,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS ix_network_logs_game_created
ON network_logs(game_id, created_at);

COMMIT;