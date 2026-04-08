use serde::{Deserialize, Serialize};

// ── RoleType: all 16 official roles ──────────────────────────────
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RoleType {
    // V1-V9: Villager Faction
    Villager,
    Seer,
    Doctor,
    Soldier,
    Police,
    Monk,
    Medium,
    Undertaker,
    Fool,
    // G10-G14: Ghost Faction
    Ghost,
    QueenGhost,
    AvengerGhost,
    DeceiverGhost,
    DarkShaman,
    // S15-S16: Special Faction
    SerialKiller,
    Nemesis,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SkillType {
    Kill,
    Protect,
    CheckFaction,
    CheckAura,
    ViewDead,
    Silence,
    Block,
    Revive,
    Special,
}

impl std::fmt::Display for SkillType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", self)
    }
}

impl SkillType {
    pub fn from_code(code: &str) -> Option<Self> {
        match code.to_uppercase().as_str() {
            "GHOST_KILL" | "SK_KILL" | "KILL" => Some(SkillType::Kill),
            "DOCTOR_HEAL" | "PROTECT" => Some(SkillType::Protect),
            "SEER_INSPECT" | "INSPECT_FACTION" => Some(SkillType::CheckFaction),
            "POLICE_CHECK" | "CHECK_AURA" | "INSPECT_AURA" => Some(SkillType::CheckAura),
            "MEDIUM_VIEW" | "VIEW_DEAD" => Some(SkillType::ViewDead),
            "SILENCE" | "DARK_SHAMAN_SILENCE" => Some(SkillType::Silence),
            "BLOCK_CHECK" | "MONK_BLOCK" => Some(SkillType::Block),
            "RECONSTRUCT" | "REVIVE" => Some(SkillType::Revive),
            _ => Some(SkillType::Special),
        }
    }
}

impl RoleType {
    pub fn from_role_id(id: i32) -> Self {
        match id {
            1 => RoleType::Villager,
            2 => RoleType::Seer,
            3 => RoleType::Doctor,
            4 => RoleType::Soldier,
            5 => RoleType::Police,
            6 => RoleType::Monk,
            7 => RoleType::Medium,
            8 => RoleType::Undertaker,
            9 => RoleType::Fool,
            10 => RoleType::Ghost,
            11 => RoleType::QueenGhost,
            12 => RoleType::AvengerGhost,
            13 => RoleType::DeceiverGhost,
            14 => RoleType::DarkShaman,
            15 => RoleType::SerialKiller,
            16 => RoleType::Nemesis,
            _ => RoleType::Villager,
        }
    }

    pub fn from_code(code: &str) -> Self {
        match code.to_uppercase().as_str() {
            "VILLAGER"      => RoleType::Villager,
            "SEER"          => RoleType::Seer,
            "DOCTOR"        => RoleType::Doctor,
            "SOLDIER"       => RoleType::Soldier,
            "POLICE"        => RoleType::Police,
            "MONK"          => RoleType::Monk,
            "MEDIUM"        => RoleType::Medium,
            "UNDERTAKER"    => RoleType::Undertaker,
            "FOOL"          => RoleType::Fool,
            "GHOST"         => RoleType::Ghost,
            "QUEENGHOST"    => RoleType::QueenGhost,
            "AVENGERGHOST"  => RoleType::AvengerGhost,
            "DECEIVERGHOST" => RoleType::DeceiverGhost,
            "DARKSHAMAN"    => RoleType::DarkShaman,
            "SERIALKILLER"  => RoleType::SerialKiller,
            "NEMESIS"       => RoleType::Nemesis,
            _               => RoleType::Villager,
        }
    }
    
    pub fn to_code(&self) -> &'static str {
        match self {
            RoleType::Villager      => "VILLAGER",
            RoleType::Seer          => "SEER",
            RoleType::Doctor        => "DOCTOR",
            RoleType::Soldier       => "SOLDIER",
            RoleType::Police        => "POLICE",
            RoleType::Monk          => "MONK",
            RoleType::Medium        => "MEDIUM",
            RoleType::Undertaker    => "UNDERTAKER",
            RoleType::Fool          => "FOOL",
            RoleType::Ghost         => "GHOST",
            RoleType::QueenGhost    => "QUEENGHOST",
            RoleType::AvengerGhost  => "AVENGERGHOST",
            RoleType::DeceiverGhost => "DECEIVERGHOST",
            RoleType::DarkShaman    => "DARKSHAMAN",
            RoleType::SerialKiller  => "SERIALKILLER",
            RoleType::Nemesis       => "NEMESIS",
        }
    }
}

// ── Faction ───────────────────────────────────────────────────────
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Faction {
    Villager,
    Ghost,
    Special,
    Draw,
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

// ── Role (Runtime Logic State) ───────────────────────────────────
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Role {
    pub role_id:     i32,
    pub role_code:   String,
    pub role_type:   RoleType,
    pub name:        String,
    pub faction:     Faction,
    pub aura_result: String, // "GOOD" | "EVIL"
    pub seer_result: String, // "VILLAGER" | "GHOST"
    pub description: String,
}

impl Role {
    pub fn new(role_type: RoleType) -> Self {
        let code = role_type.to_code().to_string();
        match role_type {
            RoleType::Villager => Self::make(1,  code, RoleType::Villager, "ชาวบ้าน", Faction::Villager, "GOOD", "VILLAGER", "ไม่มีพลังพิเศษ"),
            RoleType::Seer     => Self::make(2,  code, RoleType::Seer,     "ร่างทรง",  Faction::Special,  "GOOD", "VILLAGER", "ตรวจสังกัดต่อคืน"),
            RoleType::Doctor   => Self::make(3,  code, RoleType::Doctor,   "แพทย์",    Faction::Special,  "GOOD", "VILLAGER", "ปกป้อง 1 คน/คืน"),
            RoleType::Soldier  => Self::make(4,  code, RoleType::Soldier,  "ทหาร",     Faction::Special,  "GOOD", "VILLAGER", "ภูมิคุ้มกันตัวเอง 1 ครั้ง"),
            RoleType::Police   => Self::make(5,  code, RoleType::Police,   "ตำรวจ",    Faction::Special,  "GOOD", "VILLAGER", "ตรวจออร่า/คืน"),
            RoleType::Monk     => Self::make(6,  code, RoleType::Monk,     "พระธุดงค์",Faction::Special,  "GOOD", "VILLAGER", "ปิดการตรวจสอบ"),
            RoleType::Medium   => Self::make(7,  code, RoleType::Medium,   "หมอผีคุณไสย",Faction::Special,"GOOD", "VILLAGER", "ดูบทบาทผู้ตาย"),
            RoleType::Undertaker=>Self::make(8,  code, RoleType::Undertaker,"สัปเหร่อ",  Faction::Special,  "GOOD", "VILLAGER", "ดูบทบาทของผู้ถูกโหวตออก"),
            RoleType::Fool     => Self::make(9,  code, RoleType::Fool,     "คนดวงซวย", Faction::Special,  "GOOD", "VILLAGER", "ชนะถ้าถูกโหวตออก"),
            RoleType::Ghost    => Self::make(10, code, RoleType::Ghost,    "ผีปอบ",    Faction::Ghost,    "EVIL", "GHOST",    "ฆ่าชาวบ้านทุกคืน"),
            RoleType::QueenGhost    => Self::make(11, code, RoleType::QueenGhost,    "ผีกระสือใหญ่",  Faction::Ghost, "EVIL", "GHOST", "ออร่าหลอก — GOOD"),
            RoleType::AvengerGhost  => Self::make(12, code, RoleType::AvengerGhost,  "ผีตายโหง",      Faction::Ghost, "EVIL", "GHOST", "ตายโหง → ลากคนตาย 1 คน"),
            RoleType::DeceiverGhost => Self::make(13, code, RoleType::DeceiverGhost, "ผีเปรต",         Faction::Ghost, "EVIL", "GHOST", "หลอก Seer ว่าเป็น VILLAGER"),
            RoleType::DarkShaman    => Self::make(14, code, RoleType::DarkShaman,    "หมอผีดำ",        Faction::Ghost, "EVIL", "GHOST", "ทำให้เงียบ 1 คน/คืน"),
            RoleType::SerialKiller  => Self::make(15, code, RoleType::SerialKiller,  "ฆาตกรต่อเนื่อง", Faction::Special,"EVIL","VILLAGER","ฆ่าทุกคืน, ชนะถ้าเหลือคนสุดท้าย"),
            RoleType::Nemesis       => Self::make(16, code, RoleType::Nemesis,       "เจ้ากรรมนายเวร", Faction::Special,"GOOD","VILLAGER","ชนะถ้าเป้าหมายลับถูกโหวตออก"),
        }
    }

    fn make(role_id: i32, role_code: String, role_type: RoleType, name: &str, faction: Faction, aura: &str, seer: &str, desc: &str) -> Self {
        Self {
            role_id,
            role_code,
            role_type,
            name: name.to_string(),
            faction,
            aura_result: aura.to_string(),
            seer_result: seer.to_string(),
            description: desc.to_string(),
        }
    }
}
