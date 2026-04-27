-- Align roles catalog with CN321 werewolf roles PDF (16 roles)
-- and ensure optional columns exist for older databases.

ALTER TABLE roles
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS skill_1 text,
  ADD COLUMN IF NOT EXISTS skill_2 text,
  ADD COLUMN IF NOT EXISTS seer_result text,
  ADD COLUMN IF NOT EXISTS aura_result text;

WITH desired(role_code, role_name, faction, description, skill_1, skill_2, seer_result, aura_result) AS (
  VALUES
    ('V1', 'ชาวบ้าน', 'VILLAGER', 'ไม่มีพลังพิเศษ พูดคุยและโหวตช่วงกลางวัน', NULL, NULL, 'VILLAGER', 'GOOD'),
    ('V2', 'ร่างทรง', 'VILLAGER', 'ตรวจฝ่ายของผู้เล่น 1 คนทุกคืน (ผลเป็น ชาวบ้าน/ผี)', 'ตรวจฝ่ายผู้เล่น 1 คน', NULL, 'VILLAGER', 'GOOD'),
    ('V3', 'แพทย์', 'VILLAGER', 'ปกป้องผู้เล่น 1 คนทุกคืน หากกันการโจมตีสำเร็จ พลังป้องกันจะหมดถาวร', 'ปกป้องผู้เล่น 1 คน', 'ห้ามปกป้องคนเดิมติดกัน', 'VILLAGER', 'GOOD'),
    ('V4', 'ทหาร', 'VILLAGER', 'ปกป้องผู้เล่น 1 คนทุกคืน หากเป้าหมายถูกโจมตี ทหารตายแทน', 'รับการโจมตีแทนเป้าหมาย', NULL, 'VILLAGER', 'GOOD'),
    ('V5', 'ตำรวจ', 'VILLAGER', 'เลือกผู้เล่น 2 คนทุกคืน เพื่อดูว่าอยู่ฝ่ายเดียวกันหรือไม่', 'ตรวจผู้เล่น 2 คนว่าอยู่ฝ่ายเดียวกันหรือไม่', NULL, 'VILLAGER', 'GOOD'),
    ('V6', 'พระธุดงค์', 'VILLAGER', 'ตรวจออร่าผู้เล่น 1 คนทุกคืน (ดี/ชั่ว)', 'ตรวจออร่าผู้เล่น 1 คน', NULL, 'VILLAGER', 'GOOD'),
    ('V7', 'หมอผีคุณไสย', 'VILLAGER', 'มีพลัง 2 อย่าง ใช้ได้อย่างละ 1 ครั้งตลอดเกม', 'ชุบชีวิตผู้เล่นที่ตายในคืนนั้น', 'ฆ่าผู้เล่น 1 คน', 'VILLAGER', 'GOOD'),
    ('V8', 'สัปเหร่อ', 'VILLAGER', 'เมื่อมีผู้เล่นตาย สามารถดูบทบาทผู้ตายได้ 1 คนต่อคืน', 'ดูบทบาทผู้ตาย 1 คน', NULL, 'VILLAGER', 'GOOD'),
    ('V9', 'คนดวงซวย', 'VILLAGER', 'เริ่มเกมเป็นชาวบ้าน หากถูกผีโจมตีครั้งแรกจะไม่ตายและเปลี่ยนเป็นฝ่ายผีปอบ', 'เปลี่ยนฝ่ายเมื่อถูกโจมตีครั้งแรก', NULL, 'VILLAGER', 'GOOD'),
    ('G10', 'ผีปอบ', 'GHOST', 'ร่วมกับฝ่ายผีเลือกฆ่าผู้เล่น 1 คนทุกคืน', 'ร่วมกันฆ่าผู้เล่น 1 คนทุกคืน', NULL, 'GHOST', 'EVIL'),
    ('G11', 'ผีกระสือใหญ่', 'GHOST', 'หัวหน้าฝ่ายผี และให้ผลตรวจออร่าเป็นดี', 'ร่วมกันฆ่าผู้เล่น 1 คนทุกคืน', 'ผลตรวจออร่าเป็นดี', 'GHOST', 'GOOD'),
    ('G12', 'ผีตายโหง', 'GHOST', 'หากถูกโหวตตายในกลางวัน สามารถเลือกผู้เล่น 1 คนตายตามทันที', 'ตายลาก 1 คนเมื่อถูกโหวตกลางวัน', NULL, 'GHOST', 'EVIL'),
    ('G13', 'ผีเปรต', 'GHOST', 'ร่างทรงและพระธุดงค์ตรวจไม่พบ (ผลตรวจเป็นดี)', 'หลอกผลตรวจให้เป็นดี', 'ร่วมกันฆ่าผู้เล่น 1 คนทุกคืน', 'VILLAGER', 'GOOD'),
    ('G14', 'หมอผีดำ', 'GHOST', 'เลือกอย่างใดอย่างหนึ่งทุกคืน', 'ปกป้องผี 1 ตัว', 'สาปผู้เล่น 1 คนให้พูดไม่ได้กลางวัน', 'GHOST', 'EVIL'),
    ('S15', 'ฆาตกรต่อเนื่อง', 'SPECIAL', 'เล่นเดี่ยว ฆ่าผู้เล่น 1 คนทุกคืน ชนะเมื่อเหลือคนสุดท้าย', 'ฆ่าผู้เล่น 1 คนทุกคืน', NULL, 'VILLAGER', 'EVIL'),
    ('S16', 'เจ้ากรรมนายเวร', 'SPECIAL', 'มีเป้าหมายลับตั้งแต่เริ่มเกม หากเป้าหมายตายจะชนะทันที', 'ชนะทันทีเมื่อเป้าหมายลับตาย', NULL, 'VILLAGER', 'GOOD')
)
UPDATE roles r
SET
  role_code = d.role_code,
  role_name = d.role_name,
  faction = d.faction,
  description = d.description,
  skill_1 = d.skill_1,
  skill_2 = d.skill_2,
  seer_result = d.seer_result,
  aura_result = d.aura_result
FROM desired d
WHERE r.role_code = d.role_code OR r.role_name = d.role_name;

WITH desired(role_code, role_name, faction, description, skill_1, skill_2, seer_result, aura_result) AS (
  VALUES
    ('V1', 'ชาวบ้าน', 'VILLAGER', 'ไม่มีพลังพิเศษ พูดคุยและโหวตช่วงกลางวัน', NULL, NULL, 'VILLAGER', 'GOOD'),
    ('V2', 'ร่างทรง', 'VILLAGER', 'ตรวจฝ่ายของผู้เล่น 1 คนทุกคืน (ผลเป็น ชาวบ้าน/ผี)', 'ตรวจฝ่ายผู้เล่น 1 คน', NULL, 'VILLAGER', 'GOOD'),
    ('V3', 'แพทย์', 'VILLAGER', 'ปกป้องผู้เล่น 1 คนทุกคืน หากกันการโจมตีสำเร็จ พลังป้องกันจะหมดถาวร', 'ปกป้องผู้เล่น 1 คน', 'ห้ามปกป้องคนเดิมติดกัน', 'VILLAGER', 'GOOD'),
    ('V4', 'ทหาร', 'VILLAGER', 'ปกป้องผู้เล่น 1 คนทุกคืน หากเป้าหมายถูกโจมตี ทหารตายแทน', 'รับการโจมตีแทนเป้าหมาย', NULL, 'VILLAGER', 'GOOD'),
    ('V5', 'ตำรวจ', 'VILLAGER', 'เลือกผู้เล่น 2 คนทุกคืน เพื่อดูว่าอยู่ฝ่ายเดียวกันหรือไม่', 'ตรวจผู้เล่น 2 คนว่าอยู่ฝ่ายเดียวกันหรือไม่', NULL, 'VILLAGER', 'GOOD'),
    ('V6', 'พระธุดงค์', 'VILLAGER', 'ตรวจออร่าผู้เล่น 1 คนทุกคืน (ดี/ชั่ว)', 'ตรวจออร่าผู้เล่น 1 คน', NULL, 'VILLAGER', 'GOOD'),
    ('V7', 'หมอผีคุณไสย', 'VILLAGER', 'มีพลัง 2 อย่าง ใช้ได้อย่างละ 1 ครั้งตลอดเกม', 'ชุบชีวิตผู้เล่นที่ตายในคืนนั้น', 'ฆ่าผู้เล่น 1 คน', 'VILLAGER', 'GOOD'),
    ('V8', 'สัปเหร่อ', 'VILLAGER', 'เมื่อมีผู้เล่นตาย สามารถดูบทบาทผู้ตายได้ 1 คนต่อคืน', 'ดูบทบาทผู้ตาย 1 คน', NULL, 'VILLAGER', 'GOOD'),
    ('V9', 'คนดวงซวย', 'VILLAGER', 'เริ่มเกมเป็นชาวบ้าน หากถูกผีโจมตีครั้งแรกจะไม่ตายและเปลี่ยนเป็นฝ่ายผีปอบ', 'เปลี่ยนฝ่ายเมื่อถูกโจมตีครั้งแรก', NULL, 'VILLAGER', 'GOOD'),
    ('G10', 'ผีปอบ', 'GHOST', 'ร่วมกับฝ่ายผีเลือกฆ่าผู้เล่น 1 คนทุกคืน', 'ร่วมกันฆ่าผู้เล่น 1 คนทุกคืน', NULL, 'GHOST', 'EVIL'),
    ('G11', 'ผีกระสือใหญ่', 'GHOST', 'หัวหน้าฝ่ายผี และให้ผลตรวจออร่าเป็นดี', 'ร่วมกันฆ่าผู้เล่น 1 คนทุกคืน', 'ผลตรวจออร่าเป็นดี', 'GHOST', 'GOOD'),
    ('G12', 'ผีตายโหง', 'GHOST', 'หากถูกโหวตตายในกลางวัน สามารถเลือกผู้เล่น 1 คนตายตามทันที', 'ตายลาก 1 คนเมื่อถูกโหวตกลางวัน', NULL, 'GHOST', 'EVIL'),
    ('G13', 'ผีเปรต', 'GHOST', 'ร่างทรงและพระธุดงค์ตรวจไม่พบ (ผลตรวจเป็นดี)', 'หลอกผลตรวจให้เป็นดี', 'ร่วมกันฆ่าผู้เล่น 1 คนทุกคืน', 'VILLAGER', 'GOOD'),
    ('G14', 'หมอผีดำ', 'GHOST', 'เลือกอย่างใดอย่างหนึ่งทุกคืน', 'ปกป้องผี 1 ตัว', 'สาปผู้เล่น 1 คนให้พูดไม่ได้กลางวัน', 'GHOST', 'EVIL'),
    ('S15', 'ฆาตกรต่อเนื่อง', 'SPECIAL', 'เล่นเดี่ยว ฆ่าผู้เล่น 1 คนทุกคืน ชนะเมื่อเหลือคนสุดท้าย', 'ฆ่าผู้เล่น 1 คนทุกคืน', NULL, 'VILLAGER', 'EVIL'),
    ('S16', 'เจ้ากรรมนายเวร', 'SPECIAL', 'มีเป้าหมายลับตั้งแต่เริ่มเกม หากเป้าหมายตายจะชนะทันที', 'ชนะทันทีเมื่อเป้าหมายลับตาย', NULL, 'VILLAGER', 'GOOD')
)
INSERT INTO roles (
  role_code,
  role_name,
  faction,
  description,
  skill_1,
  skill_2,
  seer_result,
  aura_result
)
SELECT
  d.role_code,
  d.role_name,
  d.faction,
  d.description,
  d.skill_1,
  d.skill_2,
  d.seer_result,
  d.aura_result
FROM desired d
WHERE NOT EXISTS (
  SELECT 1 FROM roles r
  WHERE r.role_code = d.role_code OR r.role_name = d.role_name
);
