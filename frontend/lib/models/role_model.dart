class RoleData {
  final int roleId;
  final String roleCode;
  final String roleName;
  final String faction;
  final String auraResult;
  final String seerResult;
  final String? description;
  final int minPlayers;
  final int maxPlayers;
  final bool isUnique;
  final int rolePriority;
  final String? imagePath;

  RoleData({
    required this.roleId,
    required this.roleCode,
    required this.roleName,
    required this.faction,
    required this.auraResult,
    required this.seerResult,
    this.description,
    this.minPlayers = 1,
    this.maxPlayers = 16,
    this.isUnique = true,
    this.rolePriority = 0,
    this.imagePath,
  });

  factory RoleData.fromJson(Map<String, dynamic> json) {
    return RoleData(
      roleId: json['role_id'] ?? json['roleId'] ?? 0,
      roleCode: json['role_code'] ?? json['roleCode'] ?? '',
      roleName: json['role_name'] ?? json['roleName'] ?? '',
      faction: json['faction'] ?? '',
      auraResult: json['aura_result'] ?? json['auraResult'] ?? '',
      seerResult: json['seer_result'] ?? json['seerResult'] ?? '',
      description: json['description'],
      minPlayers: json['min_players'] ?? json['minPlayers'] ?? 1,
      maxPlayers: json['max_players'] ?? json['maxPlayers'] ?? 16,
      isUnique: json['is_unique'] ?? json['isUnique'] ?? true,
      rolePriority: json['role_priority'] ?? json['rolePriority'] ?? 0,
      imagePath: json['role_img'] ?? _mapCodeToAsset(json['role_code'] ?? json['roleCode'] ?? ''),
    );
  }

  static String _mapCodeToAsset(String code) {
    switch (code.toUpperCase()) {
      case 'VILLAGER': return 'assets/images/V01.jpg';
      case 'SEER': return 'assets/images/V02.jpg';
      case 'DOCTOR': return 'assets/images/V03.jpg';
      case 'GHOST': return 'assets/images/G01.jpg';
      case 'UNDERTAKER': return 'assets/images/V01.jpg';
      default: return 'assets/images/V01.jpg';
    }
  }
}

class SkillData {
  final String skillId;
  final String skillCode;
  final String skillName;
  final String type; // renamed from skillType to match schema target_type or similar
  final String phase;
  final int? maxUses;
  final String? description;
  final String? imagePath;

  SkillData({
    required this.skillId,
    required this.skillCode,
    required this.skillName,
    required this.type,
    required this.phase,
    this.maxUses,
    this.description,
    this.imagePath,
  });

  factory SkillData.fromJson(Map<String, dynamic> json) {
    return SkillData(
      skillId: json['skill_id']?.toString() ?? json['skillId']?.toString() ?? '',
      skillCode: json['skill_code'] ?? json['skillCode'] ?? '',
      skillName: json['skill_name'] ?? json['skillName'] ?? '',
      type: json['target_type'] ?? json['skillType'] ?? '',
      phase: json['phase_type'] ?? json['phaseType'] ?? '',
      maxUses: json['usage_limit'] ?? json['usageLimit'],
      description: json['description'],
      imagePath: json['skill_img'] ?? _mapCodeToAsset(json['skill_code'] ?? json['skillCode'] ?? ''),
    );
  }

  static String _mapCodeToAsset(String code) {
    switch (code.toUpperCase()) {
      case 'SEER_INSPECT': return 'assets/images/skill_eye.png';
      case 'DOCTOR_HEAL': return 'assets/images/skill_heal.png';
      case 'VILLAGE_VOTE': return 'assets/images/Sign.png';
      case 'GHOST_KILL': return 'assets/images/skill_voodoo.png';
      case 'UNDERTAKER_CHECK': return 'assets/images/skill_eye.png';
      default: return 'assets/images/skill_eye.png';
    }
  }
}
