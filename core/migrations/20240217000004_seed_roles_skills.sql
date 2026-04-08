BEGIN;

-- =========================
-- SEED ROLES (16 roles)
-- =========================

-- Villager Faction (9 roles)
INSERT INTO roles (role_code, role_name, faction, seer_result, aura_result, min_players, max_players, is_unique, role_priority)
VALUES
  ('VILLAGER',   'ชาวบ้าน',        'VILLAGER', 'VILLAGER', 'GOOD', 1,  16, false, 0),
  ('SEER',       'ร่างทรง',         'VILLAGER', 'VILLAGER', 'GOOD', 4,  16, true,  2),
  ('DOCTOR',     'แพทย์',           'VILLAGER', 'VILLAGER', 'GOOD', 4,  16, true,  2),
  ('SOLDIER',    'ทหาร',            'VILLAGER', 'VILLAGER', 'GOOD', 6,  16, true,  2),
  ('POLICE',     'ตำรวจ',           'VILLAGER', 'VILLAGER', 'GOOD', 6,  16, true,  2),
  ('MONK',       'พระธุดงค์',       'VILLAGER', 'VILLAGER', 'GOOD', 7,  16, true,  2),
  ('MEDIUM',     'หมอผีคุณไสย',     'VILLAGER', 'VILLAGER', 'GOOD', 7,  16, true,  2),
  ('UNDERTAKER', 'สัปเหร่อ',        'VILLAGER', 'VILLAGER', 'GOOD', 8,  16, true,  2),
  ('FOOL',       'คนดวงซวย',        'VILLAGER', 'VILLAGER', 'GOOD', 6,  16, true,  1)
ON CONFLICT (role_code) DO NOTHING;

-- Ghost Faction (5 roles)
INSERT INTO roles (role_code, role_name, faction, seer_result, aura_result, min_players, max_players, is_unique, role_priority)
VALUES
  ('GHOST',         'ผีปอบ',          'GHOST', 'GHOST',    'EVIL', 4,  16, false, 3),
  ('QUEENGHOST',    'ผีกระสือใหญ่',   'GHOST', 'GHOST',    'GOOD', 7,  16, true,  3),
  ('AVENGERGHOST',  'ผีตายโหง',       'GHOST', 'GHOST',    'EVIL', 7,  16, true,  3),
  ('DECEIVERGHOST', 'ผีเปรต',         'GHOST', 'VILLAGER', 'EVIL', 7,  16, true,  3),
  ('DARKSHAMAN',    'หมอผีดำ',        'GHOST', 'GHOST',    'EVIL', 9,  16, true,  3)
ON CONFLICT (role_code) DO NOTHING;

-- Special Faction (2 roles)
INSERT INTO roles (role_code, role_name, faction, seer_result, aura_result, min_players, max_players, is_unique, role_priority)
VALUES
  ('SERIALKILLER', 'ฆาตกรต่อเนื่อง', 'SPECIAL', 'VILLAGER', 'EVIL', 7,  16, true, 4),
  ('NEMESIS',      'เจ้ากรรมนายเวร', 'SPECIAL', 'VILLAGER', 'GOOD', 13, 16, true, 1)
ON CONFLICT (role_code) DO NOTHING;

-- =========================
-- SEED SKILLS (11 skills)
-- =========================
INSERT INTO skills (skill_code, skill_name, skill_type, phase, max_uses)
VALUES
  ('KILL',              'Kill',                'KILL',    'NIGHT', NULL),
  ('PROTECT',           'Protect',             'PROTECT', 'NIGHT', NULL),
  ('INSPECT_FACTION',   'Inspect Faction',     'CHECK',   'NIGHT', NULL),
  ('INSPECT_AURA',      'Inspect Aura',        'CHECK',   'NIGHT', NULL),
  ('BLOCK_CHECK',       'Block Check',         'SPECIAL', 'NIGHT', NULL),
  ('VIEW_DEAD_ROLE',    'View Dead Role',      'CHECK',   'NIGHT', NULL),
  ('SILENCE',           'Silence',             'SPECIAL', 'NIGHT', NULL),
  ('SELF_PROTECT',      'Self Protect',        'PROTECT', 'NIGHT', 1),
  ('DRAG_TO_DEATH',     'Drag to Death',       'KILL',    'DAY',   1),
  ('FOOL_VICTORY',      'Fool Victory',        'PASSIVE', 'DAY',   NULL),
  ('HIDDEN_TARGET_WIN', 'Hidden Target Win',   'PASSIVE', 'DAY',   NULL)
ON CONFLICT (skill_code) DO NOTHING;

-- =========================
-- SEED ROLE_SKILLS MAPPINGS
-- =========================

-- Ghost faction kills
INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'GHOST' AND s.skill_code = 'KILL'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'QUEENGHOST' AND s.skill_code = 'KILL'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'AVENGERGHOST' AND s.skill_code IN ('KILL', 'DRAG_TO_DEATH')
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'DECEIVERGHOST' AND s.skill_code = 'KILL'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'DARKSHAMAN' AND s.skill_code IN ('KILL', 'SILENCE')
ON CONFLICT (role_id, skill_id) DO NOTHING;

-- Special faction kills
INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'SERIALKILLER' AND s.skill_code = 'KILL'
ON CONFLICT (role_id, skill_id) DO NOTHING;

-- Villager faction skills
INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'SEER' AND s.skill_code = 'INSPECT_FACTION'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'DOCTOR' AND s.skill_code = 'PROTECT'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'SOLDIER' AND s.skill_code = 'SELF_PROTECT'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'POLICE' AND s.skill_code = 'INSPECT_AURA'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'MONK' AND s.skill_code = 'BLOCK_CHECK'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'MEDIUM' AND s.skill_code = 'VIEW_DEAD_ROLE'
ON CONFLICT (role_id, skill_id) DO NOTHING;

-- Special passive skills
INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'FOOL' AND s.skill_code = 'FOOL_VICTORY'
ON CONFLICT (role_id, skill_id) DO NOTHING;

INSERT INTO role_skills (role_id, skill_id)
SELECT r.role_id, s.skill_id
FROM roles r, skills s
WHERE r.role_code = 'NEMESIS' AND s.skill_code = 'HIDDEN_TARGET_WIN'
ON CONFLICT (role_id, skill_id) DO NOTHING;

COMMIT;
