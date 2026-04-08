// ── RoleType ──────────────────────────────────────────────────────
// Pulled from build.rs generated file at compile time.
// To add a new role: edit `build.rs`, add the row, recompile.
include!(concat!(env!("OUT_DIR"), "/role_type.rs"));

// ── Faction ───────────────────────────────────────────────────────
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Faction {
    Villager,
    Ghost,
    Special,
    Draw, // Indicates no clear victor (draw condition)
}

impl Faction {
    pub fn from_str(s: &str) -> Self {
        match s.to_uppercase().as_str() {
            "GHOST"   => Faction::Ghost,
            "SPECIAL" => Faction::Special,
            _         => Faction::Villager,
        }
    }
}

// ── SkillType ─────────────────────────────────────────────────────
/// All possible skill behaviors. Adding a new skill type here
/// covers it in the engine automatically — no per-role match needed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SkillType {
    /// Ghost/SK: register a kill intent
    Kill,
    /// Doctor/Soldier: protect a target from being killed this night
    Protect,
    /// Seer: reveal faction (VILLAGER/GHOST)
    CheckFaction,
    /// Monk (Police): reveal aura (GOOD/EVIL)
    CheckAura,
    /// Medium: view dead player's role
    ViewDead,
    /// DarkShaman: silence a player (can't speak next day)
    Silence,
    /// Future: revive / swap / etc.
    Revive,
}

impl SkillType {
    pub fn from_code(code: &str) -> Option<Self> {
        match code.to_uppercase().as_str() {
            "KILL"          | "GHOST_KILL" | "SK_KILL"  => Some(SkillType::Kill),
            "PROTECT"       | "DOCTOR_HEAL"             => Some(SkillType::Protect),
            "CHECK_FACTION" | "SEER_INSPECT"            => Some(SkillType::CheckFaction),
            "CHECK_AURA"    | "POLICE_CHECK"            => Some(SkillType::CheckAura),
            "VIEW_DEAD"     | "UNDERTAKER_CHECK"        => Some(SkillType::ViewDead),
            "SILENCE"       | "DARKSHAMAN_SILENCE"      => Some(SkillType::Silence),
            "REVIVE"                                    => Some(SkillType::Revive),
            _ => None,
        }
    }
}

// ── Skill ─────────────────────────────────────────────────────────
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Skill {
    pub skill_type: SkillType,
    /// None = unlimited uses per game
    pub max_uses: Option<u32>,
    /// Night, Day, or Any
    pub phase: String,
    pub description: String,
}

impl Skill {
    pub fn new(skill_type: SkillType, max_uses: Option<u32>, phase: &str, description: &str) -> Self {
        Self {
            skill_type,
            max_uses,
            phase: phase.to_string(),
            description: description.to_string(),
        }
    }
}

// ── Role ─────────────────────────────────────────────────────────
/// Full role definition. In production this is loaded from DB cache.
/// The `skills` vec supports up to 2 skills per role.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Role {
    pub role_code: String,
    pub role_type: RoleType,
    pub name: String,
    pub faction: Faction,
    pub aura_result: String,  // "GOOD" | "EVIL"
    pub seer_result: String,  // "VILLAGER" | "GHOST"
    pub description: String,
    pub skills: Vec<Skill>,   // 0..=2 skills
}

impl Role {
    /// Build a default Role from a DB-loaded role_code.
    /// Skills are populated from DB-loaded skill data in production.
    /// This in-process fallback is used for tests / initial seeding.
    pub fn from_code(code: &str) -> Self {
        let role_type = RoleType::from_code(code);
        match role_type {
            RoleType::Villager => Self::make(
                code, role_type, "ชาวบ้าน", Faction::Villager,
                "GOOD", "VILLAGER", "ไม่มีพลังพิเศษ ", vec![],
            ),
            RoleType::Seer => Self::make(
                code, role_type, "ร่างทรง", Faction::Special,
                "GOOD", "VILLAGER", "ตรวจสอบสังกัดผู้เล่นทุกคืน",
                vec![Skill::new(SkillType::CheckFaction, None, "NIGHT", "ตรวจสอบว่าเป็นผีหรือไม่")],
            ),
            RoleType::Doctor => Self::make(
                code, role_type, "แพทย์", Faction::Special,
                "GOOD", "VILLAGER", "ปกป้องผู้เล่นหนึ่งคนทุกคืน",
                vec![Skill::new(SkillType::Protect, None, "NIGHT", "ปกป้องจากการตาย")],
            ),
            RoleType::Soldier => Self::make(
                code, role_type, "ทหาร", Faction::Special,
                "GOOD", "VILLAGER", "ภูมิคุ้มกันตัวเองจากการถูกฆ่า 1 ครั้ง",
                vec![Skill::new(SkillType::Protect, Some(1), "NIGHT", "ปกป้องตัวเอง 1 ครั้ง")],
            ),
            RoleType::Police => Self::make(
                code, role_type, "ตำรวจ", Faction::Special,
                "GOOD", "VILLAGER", "ตรวจสอบออร่าของผู้เล่นทุกคืน",
                vec![Skill::new(SkillType::CheckAura, None, "NIGHT", "ตรวจสอบออร่า GOOD/EVIL")],
            ),
            RoleType::Monk => Self::make(
                code, role_type, "พระธุดงค์", Faction::Special,
                "GOOD", "VILLAGER", "ปิดหน้าผู้เล่นให้ร่างทรงไม่เห็นสังกัด",
                vec![Skill::new(SkillType::Silence, None, "NIGHT", "บล็อกการตรวจสอบ")],
            ),
            RoleType::Medium => Self::make(
                code, role_type, "หมอผีคุณไสย", Faction::Special,
                "GOOD", "VILLAGER", "สื่อสารกับผู้ตายได้ 1 ครั้งต่อคืน",
                vec![Skill::new(SkillType::ViewDead, None, "NIGHT", "ดูบทบาทของคนตาย")],
            ),
            RoleType::Undertaker => Self::make(
                code, role_type, "สัปเหร่อ", Faction::Special,
                "GOOD", "VILLAGER", "ดูบทบาทของผู้ตายจากการโหวต 1 รายต่อคืน",
                vec![Skill::new(SkillType::ViewDead, None, "NIGHT", "ดูบทบาทของคนถูกประหาร")],
            ),
            RoleType::Fool => Self::make(
                code, role_type, "คนดวงซวย", Faction::Special,
                "GOOD", "VILLAGER", "ชนะหากตัวเองถูกโหวตออก", vec![],
            ),
            RoleType::Ghost => Self::make(
                code, role_type, "ผีปอบ", Faction::Ghost,
                "EVIL", "GHOST", "ฆ่าชาวบ้านทุกคืน",
                vec![Skill::new(SkillType::Kill, None, "NIGHT", "เลือกเหยื่อ")],
            ),
            RoleType::QueenGhost => Self::make(
                code, role_type, "ผีกระสือใหญ่", Faction::Ghost,
                "EVIL", "GHOST", "ออร่าหลอก — ร่างทรงมองว่าเป็นชาวบ้าน",
                vec![Skill::new(SkillType::Kill, None, "NIGHT", "เลือกเหยื่อ")],
            ),
            RoleType::AvengerGhost => Self::make(
                code, role_type, "ผีตายโหง", Faction::Ghost,
                "EVIL", "GHOST", "ถูกโหวตออก → ฆ่าเพิ่ม 1 คนทันที",
                vec![Skill::new(SkillType::Kill, None, "NIGHT", "เลือกเหยื่อ")],
            ),
            RoleType::DeceiverGhost => Self::make(
                code, role_type, "ผีเปรต", Faction::Ghost,
                "EVIL", "GHOST", "ร่างทรงตรวจแล้วเห็นเป็น VILLAGER (หลอก)",
                vec![Skill::new(SkillType::Kill, None, "NIGHT", "เลือกเหยื่อ")],
            ),
            RoleType::DarkShaman => Self::make(
                code, role_type, "หมอผีดำ", Faction::Ghost,
                "EVIL", "GHOST", "ทำให้เงียบผู้เล่น 1 คน ไม่ให้พูดวันถัดไป",
                vec![Skill::new(SkillType::Silence, None, "NIGHT", "ทำให้เงียบ")],
            ),
            RoleType::SerialKiller => Self::make(
                code, role_type, "ฆาตกรต่อเนื่อง", Faction::Special,
                "EVIL", "VILLAGER", "ฆ่าผู้เล่นทุกคืน ชนะถ้าเหลือคนเดียว",
                vec![Skill::new(SkillType::Kill, None, "NIGHT", "เลือกเหยื่อ")],
            ),
            RoleType::Nemesis => Self::make(
                code, role_type, "เจ้ากรรมนายเวร", Faction::Special,
                "GOOD", "VILLAGER", "ชนะถ้าเป้าหมายลับถูกโหวตออก", vec![],
            ),
        }
    }

    fn make(
        code: &str,
        role_type: RoleType,
        name: &str,
        faction: Faction,
        aura: &str,
        seer: &str,
        desc: &str,
        skills: Vec<Skill>,
    ) -> Self {
        Self {
            role_code: code.to_string(),
            role_type,
            name: name.to_string(),
            faction,
            aura_result: aura.to_string(),
            seer_result: seer.to_string(),
            description: desc.to_string(),
            skills,
        }
    }
}
