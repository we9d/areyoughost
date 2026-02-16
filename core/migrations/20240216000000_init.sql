-- =========================
-- 1) PLAYERS
-- =========================
CREATE TABLE IF NOT EXISTS players (
  player_id     TEXT PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  last_login    TEXT,
  CONSTRAINT username_len CHECK (length(username) BETWEEN 3 AND 20)
);

-- =========================
-- 2) PLAYER_SESSIONS
-- =========================
CREATE TABLE IF NOT EXISTS player_sessions (
  session_id           TEXT PRIMARY KEY,
  player_id            TEXT NOT NULL,
  refresh_token_hash   TEXT,
  created_at           TEXT NOT NULL,
  expires_at           TEXT NOT NULL,
  revoked_at           TEXT,
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

-- =========================
-- 3) FRIENDSHIPS
-- =========================
CREATE TABLE IF NOT EXISTS friendships (
  friendship_id  TEXT PRIMARY KEY,
  requester_id   TEXT NOT NULL,
  addressee_id   TEXT NOT NULL,
  status         TEXT NOT NULL CHECK (status IN ('PENDING','ACCEPTED','BLOCKED')),
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL,
  FOREIGN KEY (requester_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (addressee_id) REFERENCES players(player_id) ON DELETE CASCADE,
  CHECK (requester_id <> addressee_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_friendships_pair
ON friendships(requester_id, addressee_id);

-- =========================
-- 4) ROOMS
-- =========================
CREATE TABLE IF NOT EXISTS rooms (
  room_id       TEXT PRIMARY KEY,
  owner_id      TEXT NOT NULL,
  room_name     TEXT NOT NULL,
  max_players   INTEGER NOT NULL CHECK (max_players BETWEEN 1 AND 16),
  is_public     INTEGER NOT NULL CHECK (is_public IN (0,1)),
  room_status   TEXT NOT NULL CHECK (room_status IN ('WAITING','PLAYING','CLOSED')),
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  FOREIGN KEY (owner_id) REFERENCES players(player_id) ON DELETE CASCADE
);

-- =========================
-- 5) ROOM_MEMBERS
-- =========================
CREATE TABLE IF NOT EXISTS room_members (
  room_member_id  TEXT PRIMARY KEY,
  room_id         TEXT NOT NULL,
  player_id       TEXT NOT NULL,
  member_status   TEXT NOT NULL CHECK (member_status IN ('JOINED','LEFT','KICKED','LOST')),
  joined_at       TEXT NOT NULL,
  left_at         TEXT,
  lost_at         TEXT,
  FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE,
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_room_members_room_player
ON room_members(room_id, player_id);

CREATE INDEX IF NOT EXISTS ix_room_members_room
ON room_members(room_id);

-- =========================
-- 6) ROOM_INVITES
-- =========================
CREATE TABLE IF NOT EXISTS room_invites (
  invite_id     TEXT PRIMARY KEY,
  room_id       TEXT NOT NULL,
  inviter_id    TEXT NOT NULL,
  invitee_id    TEXT NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('PENDING','ACCEPTED','DECLINED','CANCELED')),
  created_at    TEXT NOT NULL,
  responded_at  TEXT,
  FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE,
  FOREIGN KEY (inviter_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (invitee_id) REFERENCES players(player_id) ON DELETE CASCADE,
  CHECK (inviter_id <> invitee_id)
);

CREATE INDEX IF NOT EXISTS ix_room_invites_room
ON room_invites(room_id);

-- =========================
-- 7) ROLES
-- Postgres: SERIAL for auto-increment int
-- =========================
CREATE TABLE IF NOT EXISTS roles (
  role_id      SERIAL PRIMARY KEY,
  role_code    TEXT NOT NULL UNIQUE,
  role_name    TEXT NOT NULL,
  faction      TEXT NOT NULL CHECK (faction IN ('VILLAGER','GHOST','SPECIAL')),
  description  TEXT,
  skill_1      TEXT,
  skill_2      TEXT
);

-- =========================
-- 8) GAMES
-- =========================
CREATE TABLE IF NOT EXISTS games (
  game_id        TEXT PRIMARY KEY,
  room_id        TEXT NOT NULL,
  started_at     TEXT NOT NULL,
  ended_at       TEXT,
  game_status    TEXT NOT NULL CHECK (game_status IN ('ONGOING','FINISHED')),
  winner_faction TEXT,
  random_seed    BIGINT NOT NULL,
  FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_games_room
ON games(room_id);

-- =========================
-- 9) GAME_PARTICIPANTS
-- =========================
CREATE TABLE IF NOT EXISTS game_participants (
  game_participant_id  TEXT PRIMARY KEY,
  game_id              TEXT NOT NULL,
  player_id            TEXT NOT NULL,
  role_id              INTEGER NOT NULL,
  is_alive             INTEGER NOT NULL CHECK (is_alive IN (0,1)),
  seat_number          INTEGER NOT NULL,
  joined_at            TEXT NOT NULL,
  died_at              TEXT,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (player_id) REFERENCES players(player_id) ON DELETE CASCADE,
  FOREIGN KEY (role_id) REFERENCES roles(role_id),
  UNIQUE (game_id, player_id),
  UNIQUE (game_id, seat_number)
);

CREATE INDEX IF NOT EXISTS ix_game_participants_game
ON game_participants(game_id);

-- =========================
-- 10) GAME_PHASES
-- =========================
CREATE TABLE IF NOT EXISTS game_phases (
  phase_id     TEXT PRIMARY KEY,
  game_id      TEXT NOT NULL,
  phase_type   TEXT NOT NULL CHECK (phase_type IN ('NIGHT','DAY','VOTE')),
  vote_scope   TEXT CHECK (vote_scope IN ('DAY','GHOST')),
  phase_order  INTEGER NOT NULL,
  started_at   TEXT NOT NULL,
  ended_at     TEXT,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  UNIQUE (game_id, phase_order),
  CHECK (
    (phase_type = 'VOTE' AND vote_scope IS NOT NULL)
    OR
    (phase_type <> 'VOTE')
  )
);

-- =========================
-- 11) GAME_ACTIONS
-- =========================
CREATE TABLE IF NOT EXISTS game_actions (
  action_id      TEXT PRIMARY KEY,
  game_id        TEXT NOT NULL,
  phase_id       TEXT NOT NULL,
  actor_id       TEXT NOT NULL,
  target_id      TEXT,
  action_type    TEXT NOT NULL,
  action_payload TEXT,
  created_at     TEXT NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id),
  FOREIGN KEY (actor_id) REFERENCES game_participants(game_participant_id),
  FOREIGN KEY (target_id) REFERENCES game_participants(game_participant_id)
);

-- =========================
-- 12) VOTES
-- =========================
CREATE TABLE IF NOT EXISTS votes (
  vote_id     TEXT PRIMARY KEY,
  game_id     TEXT NOT NULL,
  phase_id    TEXT NOT NULL,
  voter_id    TEXT NOT NULL,
  candidate_id TEXT, -- NULL = Skip Vote
  created_at  TEXT NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id),
  FOREIGN KEY (voter_id) REFERENCES game_participants(game_participant_id),
  FOREIGN KEY (candidate_id) REFERENCES game_participants(game_participant_id),
  UNIQUE (phase_id, voter_id)
);

-- =========================
-- 13) CHAT_MESSAGES
-- =========================
CREATE TABLE IF NOT EXISTS chat_messages (
  message_id   TEXT PRIMARY KEY,
  game_id      TEXT NOT NULL,
  phase_id     TEXT,
  sender_id    TEXT NOT NULL,
  chat_scope   TEXT NOT NULL CHECK (chat_scope IN ('PUBLIC','GHOST','SYSTEM')),
  message_text TEXT NOT NULL,
  created_at   TEXT NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  FOREIGN KEY (phase_id) REFERENCES game_phases(phase_id),
  FOREIGN KEY (sender_id) REFERENCES players(player_id)
);

-- =========================
-- 14) GAME_RESULTS
-- =========================
CREATE TABLE IF NOT EXISTS game_results (
  result_id       TEXT PRIMARY KEY,
  game_id         TEXT NOT NULL,
  winner_faction  TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  total_turns     INTEGER NOT NULL,
  created_at      TEXT NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE CASCADE,
  UNIQUE(game_id)
);

-- =========================
-- 15) NETWORK_LOGS
-- =========================
CREATE TABLE IF NOT EXISTS network_logs (
  log_id     TEXT PRIMARY KEY,
  game_id    TEXT,
  session_id TEXT,
  direction  TEXT NOT NULL CHECK (direction IN ('IN','OUT')),
  msg_type   TEXT NOT NULL,
  bytes      INTEGER NOT NULL,
  dropped    INTEGER NOT NULL,
  latency_ms INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(game_id) ON DELETE SET NULL
);
