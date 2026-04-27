import 'dart:convert';

import 'package:areyoughost/game/game_catalog.dart';
import 'package:areyoughost/services/app_config.dart';
import 'package:http/http.dart' as http;

class RoleDisplayItem {
  final String roleCode;
  final String roleName;
  final String faction;
  final String team;
  final String aura;
  final String description;
  final String imagePath;
  final List<RoleSkillItem> skills;

  const RoleDisplayItem({
    required this.roleCode,
    required this.roleName,
    required this.faction,
    required this.team,
    required this.aura,
    required this.description,
    required this.imagePath,
    this.skills = const <RoleSkillItem>[],
  });
}

class RoleSkillItem {
  final String name;
  final String description;
  final String imagePath;

  const RoleSkillItem({
    required this.name,
    required this.description,
    required this.imagePath,
  });
}

class RoleService {
  static const Map<String, String> _roleCodeByRoleName = <String, String>{
    GameRoles.villager: 'V1',
    GameRoles.seer: 'V2',
    GameRoles.doctor: 'V3',
    GameRoles.soldier: 'V4',
    GameRoles.police: 'V5',
    GameRoles.monk: 'V6',
    GameRoles.witch: 'V7',
    GameRoles.undertaker: 'V8',
    GameRoles.unlucky: 'V9',
    GameRoles.ghoul: 'G10',
    GameRoles.krasue: 'G11',
    GameRoles.violentGhost: 'G12',
    GameRoles.pret: 'G13',
    GameRoles.darkShaman: 'G14',
    GameRoles.serialKiller: 'S15',
    GameRoles.karma: 'S16',
  };

  static String normalizeKey(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('`', '')
        .replaceAll('“', '')
        .replaceAll('”', '');
  }

  static List<RoleSkillItem> defaultSkillsForRoleName(String roleName) {
    final code = _roleCodeByRoleName[roleName.trim()];
    if (code == null) return const <RoleSkillItem>[];
    return _skillsForRoleCode(code, null, null);
  }

  static String? actionTypeForSkill({
    required String skillName,
    String? roleName,
  }) {
    final role = (roleName ?? '').trim();
    switch (skillName.trim()) {
      case GameSkills.seerCheck:
        return 'seer_check';
      case GameSkills.auraCheck:
        return 'aura_check';
      case GameSkills.policeCheck:
        return 'police_check';
      case GameSkills.soldierStandIn:
        return 'soldier_guard';
      case GameSkills.darkProtect:
        return 'dark_protect';
      case GameSkills.darkCurse:
        return 'dark_curse';
      case GameSkills.witchRevive:
        return 'witch_revive';
      case GameSkills.witchPoison:
        return 'witch_poison';
      case GameSkills.serialKill:
        return 'serial_kill';
      case GameSkills.ghostKill:
        return 'ghost_kill';
      case GameSkills.doctorProtect:
      case GameSkills.doctorGuard:
        return role == GameRoles.soldier ? 'soldier_guard' : 'doctor_protect';
      default:
        return null;
    }
  }

  /// Resolved image URL for a canonical Thai skill title (uses storage base URL).
  static String skillImageUrl(String canonicalSkillTitle) =>
      _imagePathForSkillName(canonicalSkillTitle);

  static Future<List<RoleDisplayItem>> fetchRoles() async {
    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/roles'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception('โหลดข้อมูลบทบาทไม่สำเร็จ (HTTP ${response.statusCode})');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('รูปแบบข้อมูลบทบาทไม่ถูกต้องจากเซิร์ฟเวอร์');
    }
    final roles = (data['roles'] as List<dynamic>? ?? <dynamic>[]);
    return roles
        .map((r) => _fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  static RoleDisplayItem _fromJson(Map<String, dynamic> json) {
    final roleCode = (json['role_code'] as String? ?? '').trim().toUpperCase();
    final faction = (json['faction'] as String? ?? '').toUpperCase();
    final desc = (json['description'] as String?)?.trim();
    final s1 = (json['skill_1'] as String?)?.trim();
    final s2 = (json['skill_2'] as String?)?.trim();
    final skillsFromRoleCode = _skillsForRoleCode(roleCode, s1, s2);
    final skills = skillsFromRoleCode.isNotEmpty
        ? skillsFromRoleCode
        : <RoleSkillItem>[
            if (s1 != null && s1.isNotEmpty) _skillFromText(s1),
            if (s2 != null && s2.isNotEmpty) _skillFromText(s2),
          ];
    final details = <String>[
      if (desc != null && desc.isNotEmpty) desc,
      for (var i = 0; i < skills.length; i++)
        'สกิล ${i + 1}: ${skills[i].description}',
    ];

    return RoleDisplayItem(
      roleCode: roleCode,
      roleName: (json['role_name'] as String? ?? 'Unknown'),
      faction: faction,
      team: _teamFromFaction(faction),
      aura: _auraFromFaction(faction),
      description: details.isEmpty ? 'ไม่มีคำอธิบาย' : details.join('\n'),
      imagePath: _imagePathForRole(roleCode),
      skills: skills,
    );
  }

  static RoleSkillItem _skillFromText(String text) {
    final name = _canonicalSkillName(text);
    return RoleSkillItem(
      name: name,
      description: text.trim(),
      imagePath: _imagePathForSkillName(name),
    );
  }

  static List<RoleSkillItem> _skillsForRoleCode(
    String roleCode,
    String? skill1Text,
    String? skill2Text,
  ) {
    String descOrDefault(String? text, String fallback) {
      final v = text?.trim() ?? '';
      return v.isNotEmpty ? v : fallback;
    }

    switch (roleCode) {
      case 'V2':
        return [
          RoleSkillItem(
            name: GameSkills.seerCheck,
            description: descOrDefault(
              skill1Text,
              'ตรวจฝ่ายผู้เล่น 1 คนในตอนกลางคืน',
            ),
            imagePath: _imagePathForSkillName(GameSkills.seerCheck),
          ),
        ];
      case 'V3':
        return [
          RoleSkillItem(
            name: GameSkills.doctorGuard,
            description: descOrDefault(
              skill1Text,
              'ปกป้องผู้เล่น 1 คนในตอนกลางคืน',
            ),
            imagePath: _imagePathForSkillName(GameSkills.doctorGuard),
          ),
        ];
      case 'V4':
        return [
          RoleSkillItem(
            name: GameSkills.doctorProtect,
            description: descOrDefault(
              skill1Text,
              'เลือกผู้เล่น 1 คน ถ้าถูกโจมตีทหารจะตายแทน',
            ),
            imagePath: _imagePathForSkillName(GameSkills.doctorProtect),
          ),
        ];
      case 'V5':
        return [
          RoleSkillItem(
            name: GameSkills.policeCheck,
            description: descOrDefault(
              skill1Text,
              'ตรวจผู้เล่น 2 คนว่าอยู่ฝ่ายเดียวกันหรือไม่',
            ),
            imagePath: _imagePathForSkillName(GameSkills.policeCheck),
          ),
        ];
      case 'V6':
        return [
          RoleSkillItem(
            name: GameSkills.auraCheck,
            description: descOrDefault(
              skill1Text,
              'ตรวจออร่าผู้เล่น 1 คน',
            ),
            imagePath: _imagePathForSkillName(GameSkills.auraCheck),
          ),
        ];
      case 'V7':
        return [
          RoleSkillItem(
            name: GameSkills.witchRevive,
            description: descOrDefault(
              skill1Text,
              'ชุบชีวิตผู้เล่นที่ถูกฆ่าในคืนนั้น (ใช้ได้ 1 ครั้ง)',
            ),
            imagePath: _imagePathForSkillName(GameSkills.witchRevive),
          ),
          RoleSkillItem(
            name: GameSkills.witchPoison,
            description: descOrDefault(
              skill2Text,
              'ฆ่าผู้เล่น 1 คน (ใช้ได้ 1 ครั้ง)',
            ),
            imagePath: _imagePathForSkillName(GameSkills.witchPoison),
          ),
        ];
      case 'V8':
        return [
          RoleSkillItem(
            name: GameSkills.undertakerReveal,
            description: descOrDefault(
              skill1Text,
              'ดูบทบาทของผู้ตายได้ 1 คนต่อคืน',
            ),
            imagePath: _imagePathForSkillName(GameSkills.undertakerReveal),
          ),
        ];
      case 'V9':
        return [
          RoleSkillItem(
            name: GameSkills.jinx,
            description:
                'เริ่มเกมเป็นชาวบ้าน หากถูกผีโจมตีครั้งแรกจะไม่ตายและเปลี่ยนเป็นผีปอบทันที',
            imagePath: _imagePathForSkillName(GameSkills.jinx),
          ),
        ];
      case 'G12':
        return [
          RoleSkillItem(
            name: GameSkills.vengefulGhost,
            description: descOrDefault(
              skill1Text,
              'หากถูกโหวตตายตอนกลางวัน เลือกผู้เล่น 1 คนตายตามทันที',
            ),
            imagePath: _imagePathForSkillName(GameSkills.vengefulGhost),
          ),
        ];
      case 'G10':
      case 'G11':
      case 'G13':
        // Team ghost kill is handled by night vote flow, not skill button.
        return const <RoleSkillItem>[];
      case 'G14':
        return [
          RoleSkillItem(
            name: GameSkills.darkProtect,
            description: descOrDefault(
              skill1Text,
              'ปกป้องผี 1 ตัวในคืนนี้',
            ),
            imagePath: _imagePathForSkillName(GameSkills.darkProtect),
          ),
          RoleSkillItem(
            name: GameSkills.darkCurse,
            description: descOrDefault(
              skill2Text,
              'สาปผู้เล่น 1 คนให้พูดไม่ได้ในช่วงกลางวัน',
            ),
            imagePath: _imagePathForSkillName(GameSkills.darkCurse),
          ),
        ];
      case 'S15':
        return [
          RoleSkillItem(
            name: GameSkills.serialKill,
            description: descOrDefault(
              skill1Text,
              'ฆ่าผู้เล่น 1 คนในตอนกลางคืน',
            ),
            imagePath: _imagePathForSkillName(GameSkills.serialKill),
          ),
        ];
      case 'S16':
        return [
          RoleSkillItem(
            name: GameSkills.karmaSecret,
            description: descOrDefault(
              skill1Text,
              'หากเป้าหมายลับตายด้วยวิธีใดก็ได้ จะชนะทันที',
            ),
            imagePath: _imagePathForSkillName(GameSkills.karmaSecret),
          ),
        ];
      default:
        return const <RoleSkillItem>[];
    }
  }

  static String _skillTitleFromText(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'สกิล';
    // Preserve explicit title prefix if backend already sends it.
    if (t.contains(':')) {
      return t.split(':').first.trim();
    }
    // Fall back to first phrase before Thai/English punctuation.
    final idx = t.indexOf(RegExp(r'[(),\n]'));
    if (idx > 0) return t.substring(0, idx).trim();
    return t;
  }

  static String _canonicalSkillName(String text) {
    final raw = text.trim();
    final t = normalizeKey(text);
    if (t.contains('คนดวงซวย') || t.contains('แปลงเป็นผีปอบ')) return GameSkills.jinx;
    if (t.contains('ตายโหง') || t.contains('ตายตาม')) return GameSkills.vengefulGhost;
    if (t.contains('เป้าหมายลับ')) return GameSkills.karmaSecret;
    if (t.contains('ตาวิเศษ')) return GameSkills.seerCheck;
    if (t.contains('สอบสวน')) return GameSkills.policeCheck;
    if (t.contains('ตรวจออร่า')) return GameSkills.auraCheck;
    if (t.contains('ชุบชีวิต')) return GameSkills.witchRevive;
    if (t.contains('คุณไสยฆ่า')) return GameSkills.witchPoison;
    if (t.contains('เปิดบทผู้ตาย') || t.contains('ผู้ตาย')) {
      return GameSkills.undertakerReveal;
    }
    if (t.contains('สาป') && t.contains('พูดไม่ได้')) return GameSkills.darkCurse;
    if (t.contains('ปกป้องผี')) return GameSkills.darkProtect;
    if (t.contains('ฆ่าเดี่ยว')) return GameSkills.serialKill;
    if (t.contains('ร่วมกันฆ่า') || (t.contains('ฆ่า') && t.contains('ทุกคืน'))) {
      return GameSkills.ghostKill;
    }
    if (t.contains('ลอบสังหาร') || (t.contains('ฝ่ายผี') && t.contains('เป้าหมาย'))) {
      return GameSkills.ghostKill;
    }
    if (t.contains('คุ้มครอง')) return GameSkills.doctorGuard;
    if (t.contains('ปกป้อง')) return GameSkills.doctorProtect;
    return _skillTitleFromText(raw);
  }

  static String _imagePathForSkillName(String skillName) {
    switch (skillName) {
      case GameSkills.jinx:
        return _storagePublicUrl('Skills', 'Ghost-Jinx-Skill.jpg');
      case GameSkills.vengefulGhost:
        return _storagePublicUrl('Skills', 'Ghost-violent-death-skill.jpg');
      case GameSkills.karmaSecret:
        return _storagePublicUrl('Skills', 'Special-secret-target.jpg');
      case GameSkills.seerCheck:
        return _storagePublicUrl('Skills', 'Villager-Clairvoyance-Skill.jpg');
      case GameSkills.policeCheck:
        return _storagePublicUrl('Skills', 'Villager-Investigation-Skill.jpg');
      case GameSkills.auraCheck:
        return _storagePublicUrl('Skills', 'Villager-Aura-Skill.jpg');
      case GameSkills.doctorProtect:
        return _storagePublicUrl('Skills', 'Villager-Defense-Skill.jpg');
      case GameSkills.doctorGuard:
        return _storagePublicUrl('Skills', 'Villager-Protection-Skill.jpg');
      case GameSkills.witchRevive:
        return _storagePublicUrl('Skills', 'Villager-Resurrection-Skill.jpg');
      case GameSkills.darkProtect:
        return _storagePublicUrl('Skills', 'Ghost-Protection-Skill.jpg');
      case GameSkills.witchPoison:
        return _storagePublicUrl('Skills', 'Villager-Voodoo-Skill.jpg');
      case GameSkills.serialKill:
        return _storagePublicUrl('Skills', "Special-assassin-skill'.jpg");
      case GameSkills.darkCurse:
        return _storagePublicUrl('Skills', 'Ghost-curse-skill.jpg');
      case GameSkills.ghostKill:
        return _storagePublicUrl('Skills', "Special-assassin-skill'.jpg");
      case GameSkills.undertakerReveal:
        return _storagePublicUrl('Skills', 'Villager-Undertaker-Skill.jpg');
      default:
        return _imagePathForSkillText(skillName);
    }
  }

  static String _imagePathForSkillText(String text) {
    final t = text.toLowerCase();
    if (t.contains('คนดวงซวย') || t.contains('แปลงเป็นผีปอบ')) {
      return _storagePublicUrl('Skills', 'Ghost-Jinx-Skill.jpg');
    }
    if (t.contains('ตายโหง') || t.contains('ตายตาม')) {
      return _storagePublicUrl('Skills', 'Ghost-violent-death-skill.jpg');
    }
    if (t.contains('ตรวจ') || t.contains('สอบสวน') || t.contains('ออร่า')) {
      return _storagePublicUrl('Skills', 'Villager-Investigation-Skill.jpg');
    }
    if (t.contains('ปกป้อง') || t.contains('คุ้มครอง') || t.contains('รักษา')) {
      return _storagePublicUrl('Skills', 'Villager-Protection-Skill.jpg');
    }
    if (t.contains('ชุบชีวิต') || t.contains('คุณไสย')) {
      return _storagePublicUrl('Skills', 'Villager-Resurrection-Skill.jpg');
    }
    if (t.contains('ฆ่า') || t.contains('สังหาร') || t.contains('กำจัด')) {
      return _storagePublicUrl('Skills', 'Ghost-curse-skill.jpg');
    }
    if (t.contains('ฝ่ายผี') || t.contains('เป้าหมายในคืนนี้')) {
      return _storagePublicUrl('Skills', "Special-assassin-skill'.jpg");
    }
    if (t.contains('เปิดบทผู้ตาย') || t.contains('ผู้ตาย')) {
      return _storagePublicUrl('Skills', 'Villager-Undertaker-Skill.jpg');
    }
    if (t.contains('เป้าหมายลับ')) {
      return _storagePublicUrl('Skills', 'Special-secret-target.jpg');
    }
    return _storagePublicUrl('Skills', 'Villager-Investigation-Skill.jpg');
  }

  static String _imagePathForRole(String roleCode) {
    switch (roleCode) {
      case 'V1':
        return _storagePublicUrl('roles_img', 'Villager.jpg');
      case 'V2':
        return _storagePublicUrl('roles_img', 'Shaman.jpg');
      case 'V3':
        return _storagePublicUrl('roles_img', 'Doctor.jpg');
      case 'V4':
        return _storagePublicUrl('roles_img', 'Soldier.jpg');
      case 'V5':
        return _storagePublicUrl('roles_img', 'Police-Officer.jpg');
      case 'V6':
        return _storagePublicUrl('roles_img', 'Buddhist-Monk.jpg');
      case 'V7':
        return _storagePublicUrl('roles_img', 'Sorcerer.jpg');
      case 'V8':
        return _storagePublicUrl('roles_img', 'Gravedigger..jpg');
      case 'V9':
        return _storagePublicUrl('roles_img', 'Unlucky-Guy.jpg');
      case 'G10':
        return _storagePublicUrl('roles_img', 'Pob-Ghost.jpg');
      case 'G11':
        return _storagePublicUrl('roles_img', 'Krasue-Ghost.jpg');
      case 'G12':
        return _storagePublicUrl('roles_img', 'Unlucky-Guy-Ghost.jpg');
      case 'G13':
        return _storagePublicUrl('roles_img', 'Preta-Hungry-Ghost.jpg');
      case 'G14':
        return _storagePublicUrl('roles_img', 'Black-Magic-Witch.jpg');
      case 'S15':
        return _storagePublicUrl('roles_img', 'Serial-Killer.jpg');
      case 'S16':
        return _storagePublicUrl('roles_img', 'Karmic-Enemy.jpg');
      default:
        return roleCode.startsWith('G')
            ? _storagePublicUrl('roles_img', 'Pob-Ghost.jpg')
            : roleCode.startsWith('V')
                ? _storagePublicUrl('roles_img', 'Villager.jpg')
                : _storagePublicUrl('roles_img', 'Karmic-Enemy.jpg');
    }
  }

  static String _storagePublicUrl(String folder, String fileName) {
    final base = AppConfig.storagePublicBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final encodedFolder = Uri.encodeComponent(folder);
    final encodedFile = Uri.encodeComponent(fileName);
    return '$base/$encodedFolder/$encodedFile';
  }

  static String _teamFromFaction(String faction) {
    switch (faction) {
      case 'VILLAGER':
        return GameTeams.villagers;
      case 'GHOST':
        return GameTeams.ghosts;
      case 'SPECIAL':
        return 'พิเศษ';
      default:
        return 'ไม่ระบุ';
    }
  }

  static String _auraFromFaction(String faction) {
    switch (faction) {
      case 'VILLAGER':
        return 'ดี';
      case 'GHOST':
        return 'ร้าย';
      case 'SPECIAL':
        return 'พิเศษ';
      default:
        return 'ไม่ระบุ';
    }
  }
}

