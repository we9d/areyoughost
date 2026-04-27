/// Canonical Thai labels shared by UI, deck builder, and role code mapping.
library;

/// Thai display names for roles (aligned with server / DB catalog).
class GameRoles {
  GameRoles._();

  static const String villager = 'ชาวบ้าน';
  static const String seer = 'ร่างทรง';
  static const String doctor = 'แพทย์';
  static const String soldier = 'ทหาร';
  static const String police = 'ตำรวจ';
  static const String monk = 'พระธุดงค์';
  static const String witch = 'หมอผีคุณไสย';
  static const String undertaker = 'สัปเหร่อ';
  static const String unlucky = 'คนดวงซวย';
  static const String ghoul = 'ผีปอบ';
  static const String krasue = 'ผีกระสือใหญ่';
  static const String violentGhost = 'ผีตายโหง';
  static const String pret = 'ผีเปรต';
  static const String darkShaman = 'หมอผีดำ';
  static const String serialKiller = 'ฆาตกรต่อเนื่อง';
  static const String karma = 'เจ้ากรรมนายเวร';

  static const List<String> balancedGoodCycle = <String>[
    villager,
    seer,
    doctor,
    soldier,
    monk,
    witch,
    // Temporarily removed from random pool until end-to-end logic is aligned:
    // - police (pair-check flow is still local-only)
    // - undertaker (not wired to backend action)
  ];

  static const List<String> balancedEvilCycle = <String>[
    ghoul,
    krasue,
    violentGhost,
    pret,
    darkShaman,
    serialKiller,
  ];

  static const List<String> balancedNeutralCycle = <String>[
    unlucky,
    karma,
  ];

  /// When API catalog is missing, treat these roles as ghost faction.
  static const Set<String> ghostTeamRoles = <String>{
    ghoul,
    krasue,
    violentGhost,
    pret,
    darkShaman,
  };

  static const Set<String> independentTeamRoles = <String>{
    karma,
    serialKiller,
  };
}

/// Team labels as returned by role catalog / `_teamOfRole` fallbacks.
class GameTeams {
  GameTeams._();

  static const String villagers = 'ชาวบ้าน';
  static const String ghosts = 'ผี';
  static const String independent = 'อิสระ';
}

/// Canonical Thai skill titles used in switches and image lookup.
class GameSkills {
  GameSkills._();

  static const String seerCheck = 'สกิลตาวิเศษ';
  static const String auraCheck = 'สกิลตรวจออร่า';
  static const String undertakerReveal = 'สกิลเปิดบทผู้ตาย';
  static const String doctorProtect = 'สกิลปกป้อง';
  static const String doctorGuard = 'สกิลคุ้มครอง';
  static const String darkProtect = 'สกิลปกป้องผี';
  static const String soldierStandIn = 'สกิลยืนแทน';
  static const String darkCurse = 'สกิลสาปพูดไม่ได้';
  static const String witchRevive = 'สกิลชุบชีวิต';
  static const String ghostKill = 'สกิลลอบสังหาร';
  static const String serialKill = 'สกิลฆ่าเดี่ยว';
  static const String witchPoison = 'สกิลคุณไสยฆ่า';
  static const String policeCheck = 'สกิลสอบสวน';
  static const String karmaSecret = 'สกิลเป้าหมายลับ';
  static const String jinx = 'สกิลคนดวงซวย';
  static const String vengefulGhost = 'สกิลตายโหง';
}
