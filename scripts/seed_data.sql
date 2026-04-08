-- Official Roles & Skills Seed Data (Aligned with 24-table Schema)

BEGIN;

-- Clear existing data to ensure clean state with new IDs
TRUNCATE public.role_skills RESTART IDENTITY CASCADE;
TRUNCATE public.skills RESTART IDENTITY CASCADE;
TRUNCATE public.roles RESTART IDENTITY CASCADE;

-- ==========================================
-- 1. SEED SKILLS (Using UUIDs)
-- ==========================================

INSERT INTO public.skills (skill_id, skill_code, skill_name, description, phase_type, target_type, usage_limit, can_skip, is_enabled) VALUES
('b27c6f1a-0a1b-4c2d-8e3f-4a5b6c7d8e9f', 'VILLAGE_VOTE', 'โหวต', 'โหวตขับไล่ผู้ต้องสงสัย', 'DAY', 'SINGLE', NULL, false, true),
('c38d7a2b-1b2c-5d3e-9f4a-5b6c7d8e9f0a', 'GHOST_KILL', 'ฆ่า', 'กำจัดชาวบ้านในคืนนี้', 'NIGHT', 'SINGLE', NULL, false, true),
('d49e8b3c-2c3d-6e4f-0a5b-6c7d8e9f0a1b', 'SEER_INSPECT', 'ตรวจฝ่าย', 'ตรวจสอบฝ่ายของผู้เล่น 1 คน', 'NIGHT', 'SINGLE', NULL, true, true),
('e50f9c4d-3d4e-7f5a-1b6c-7d8e9f0a1b2c', 'DOCTOR_HEAL', 'รักษา', 'ปกป้องผู้เล่น 1 คนจากการระบุเป้าหมาย', 'NIGHT', 'SINGLE', NULL, true, true),
('f61a0d5e-4e5f-8a6b-2c7d-8e9f0a1b2c3d', 'UNDERTAKER_CHECK', 'สืบศพ', 'ตรวจสอบบทบาทของผู้เล่นที่ตายไปแล้ว', 'NIGHT', 'SINGLE', 1, true, true);

-- ==========================================
-- 2. SEED ROLES
-- ==========================================

INSERT INTO public.roles (role_code, role_name, faction, aura_result, seer_result, description, role_priority) VALUES
-- V1-V9: Villager Faction
('VILLAGER',      'ชาวบ้าน',         'VILLAGER', 'GOOD', 'VILLAGER', 'ไม่มีพลังพิเศษ ทำหน้าที่โหวตกำจัดผี', 0),
('SEER',          'ร่างทรง',          'SPECIAL',  'GOOD', 'VILLAGER', 'ตรวจสอบสังกัดผู้เล่น 1 คนต่อคืน', 10),
('DOCTOR',        'แพทย์',            'SPECIAL',  'GOOD', 'VILLAGER', 'ปกป้องผู้เล่น 1 คนจากการถูกฆ่าต่อคืน', 20),
('SOLDIER',       'ทหาร',             'SPECIAL',  'GOOD', 'VILLAGER', 'ปกป้องตัวเองจากการถูกฆ่า 1 ครั้ง', 30),
('POLICE',        'ตำรวจ',            'SPECIAL',  'GOOD', 'VILLAGER', 'ตรวจสอบออร่า GOOD/EVIL ของผู้เล่นต่อคืน', 40),
('MONK',          'พระธุดงค์',         'SPECIAL',  'GOOD', 'VILLAGER', 'ปิดการตรวจสอบของร่างทรงต่อคืน', 50),
('MEDIUM',        'หมอผีคุณไสย',       'SPECIAL',  'GOOD', 'VILLAGER', 'สื่อสารกับวิญญาณ ดูบทบาทผู้ตายต่อคืน', 60),
('UNDERTAKER',    'สัปเหร่อ',          'SPECIAL',  'GOOD', 'VILLAGER', 'ดูบทบาทของผู้ถูกโหวตออกต่อคืน', 70),
('FOOL',          'คนดวงซวย',          'SPECIAL',  'GOOD', 'VILLAGER', 'ชนะเกมทันทีหากตัวเองถูกโหวตออก', 80),
-- G10-G14: Ghost Faction
('GHOST',         'ผีปอบ',            'GHOST',    'EVIL', 'GHOST',    'ฆ่าชาวบ้านทุกคืน อย่าให้ร่างทรงจับได้', 100),
('QUEENGHOST',    'ผีกระสือใหญ่',      'GHOST',    'EVIL', 'GHOST',    'ออร่าหลอก – ร่างทรงเห็นออร่าเป็น GOOD', 110),
('AVENGERGHOST',  'ผีตายโหง',          'GHOST',    'EVIL', 'GHOST',    'ถูกโหวตออก → ลากคนตายด้วย 1 คนทันที', 120),
('DECEIVERGHOST', 'ผีเปรต',           'GHOST',    'EVIL', 'GHOST',    'ร่างทรงเห็นเป็น VILLAGER (หลอกสังกัด)', 130),
('DARKSHAMAN',    'หมอผีดำ',           'GHOST',    'EVIL', 'GHOST',    'ทำให้เงียบผู้เล่น 1 คน ไม่ให้พูดวันถัดไป', 140),
-- S15-S16: Special Faction
('SERIALKILLER',  'ฆาตกรต่อเนื่อง',    'SPECIAL',  'EVIL', 'VILLAGER', 'ฆ่าผู้เล่นทุกคืน ชนะถ้าเหลือคนสุดท้าย', 200),
('NEMESIS',       'เจ้ากรรมนายเวร',    'SPECIAL',  'GOOD', 'VILLAGER', 'ชนะถ้าเป้าหมายลับของตนถูกโหวตออก', 210);

-- ==========================================
-- 3. MAPPING (Using join to get updated IDs)
-- ==========================================

INSERT INTO public.role_skills (role_id, skill_id, skill_order)
SELECT r.role_id, s.skill_id, 0 FROM roles r, skills s
WHERE r.role_code = 'VILLAGER' AND s.skill_code = 'VILLAGE_VOTE'
UNION ALL
SELECT r.role_id, s.skill_id, 1 FROM roles r, skills s
WHERE r.role_code = 'SEER' AND s.skill_code = 'SEER_INSPECT'
UNION ALL
SELECT r.role_id, s.skill_id, 1 FROM roles r, skills s
WHERE r.role_code = 'DOCTOR' AND s.skill_code = 'DOCTOR_HEAL'
UNION ALL
SELECT r.role_id, s.skill_id, 1 FROM roles r, skills s
WHERE r.role_code = 'GHOST' AND s.skill_code = 'GHOST_KILL'
UNION ALL
SELECT r.role_id, s.skill_id, 1 FROM roles r, skills s
WHERE r.role_code = 'UNDERTAKER' AND s.skill_code = 'UNDERTAKER_CHECK';

COMMIT;
