import 'dart:async';

import 'package:flutter/material.dart';

import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_role.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_role_skill.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_full.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_role_chat.dart';
import 'package:areyoughost/ui/widgets/buttons/roles_buttons.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/models/room_model.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/services/session_manager.dart';
import 'package:areyoughost/ui/dialogs/skill_select_dialog.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/ui/widgets/roles_card.dart';
import 'package:areyoughost/ui/game/widgets/DayTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/NightTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_day.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_night.dart';
import 'package:areyoughost/ui/game/widgets/players_popup.dart';
<<<<<<< HEAD
=======
import 'package:areyoughost/ui/widgets/buttons/roles_buttons.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_result.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_single.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';
import 'package:areyoughost/ui/game/widgets/players_popup.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';
>>>>>>> 06601c709c9d8c44475a7097969fb5f815969cca

class GameScreen extends StatefulWidget {
  /// Pass room from Quick Play or from game.started event.
  /// If null, roomId is used as fallback (e.g. from WaitingRoom path).
  final RoomModel? initialRoom;
  final String roomId;
  final String? role;

  const GameScreen({
    super.key,
    this.initialRoom,
    required this.roomId,
    this.role,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  // 16 fixed slots — index 0 = slot 1, etc.
  // null means the slot is empty.
  final List<String?> _slots = List.filled(16, null);

  StreamSubscription<Map<String, dynamic>>? _sub;
  List<ChatMessage> chatMessages = [];
  List<SkillOption> currentRoleSkills = [];

  int? mySlot; // 1-based slot number that belongs to this player
  int? selectedTarget; // slot number being voted on

<<<<<<< HEAD
  bool isDay = true;
=======
  /// 🌞 Day / 🌙 Night
  bool isDay = false;
>>>>>>> 06601c709c9d8c44475a7097969fb5f815969cca

  @override
  void initState() {
    super.initState();

    // Populate initial slots from room data
    if (widget.initialRoom != null) {
      _applyRoomPlayers(widget.initialRoom!.players);
    }

<<<<<<< HEAD
    // Listen for live updates
    _sub = WsService.instance.stream.listen(_onServerMessage);

    // Mock skills
    currentRoleSkills = [
      SkillOption(name: 'Investigate', description: 'Investigate a player',
          image: 'assets/icons/investigate.png'),
      SkillOption(name: 'Protect', description: 'Protect a player',
          image: 'assets/icons/protect.png'),
=======
    chatMessages = [];
     /// ROLE INFO

    allRoles = [
      RoleInfo(
        name: 'Villager',
        description: 'A simple villager',
      ),
    ];

    /// ROLE SKILLS (MOCK) - Active for Case 5 (Day + Skills)
    currentRoleSkills = [
      SkillOption(
        name: 'สกิลตาวิเศษ',
        description: 'เลือกผู้เล่น 1 คน\nเพื่อทำการตรวจฝ่าย',
        image: 'assets/images/skill_eye.png',
      ),
      SkillOption(
        name: 'สกิลชุบชีวิต',
        description: '“ชุบชีวิตผู้เล่นที่ถูกฆ่าในคืนนี้” ',
        image: 'assets/images/skill_heal.png',
      ),
>>>>>>> 06601c709c9d8c44475a7097969fb5f815969cca
    ];
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

<<<<<<< HEAD
  // ── Helpers ───────────────────────────────────────────────────
=======
  void _handleRoleInfoTap(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const RolesDialog(),
    );
  }

  void _handleSendMessage(String text) {
    // Implement send message logic here
    print('Sending message: $text');
  }

>>>>>>> 06601c709c9d8c44475a7097969fb5f815969cca

  /// Assign players to slots in order. Each new player gets the next free slot.
  void _applyRoomPlayers(List<PlayerInfo> players) {
    SessionManager.getSession().then((session) {
      final myId = session?['userId'] ?? '';
      setState(() {
        for (int i = 0; i < 16; i++) _slots[i] = null;
        for (int i = 0; i < players.length && i < 16; i++) {
          _slots[i] = players[i].username;
          if (players[i].playerId == myId) mySlot = i + 1;
        }
      });
    });
  }

<<<<<<< HEAD
  /// Add a player to the first free slot.
  void _addPlayer(String username, String playerId) {
    SessionManager.getSession().then((session) {
      final myId = session?['userId'] ?? '';
      setState(() {
        final idx = _slots.indexWhere((s) => s == null);
        if (idx != -1) {
          _slots[idx] = username;
          if (playerId == myId) mySlot = idx + 1;
        }
      });
    });
  }

  /// Remove a player by username.
  void _removePlayer(String username) {
    setState(() {
      final idx = _slots.indexWhere((s) => s == username);
      if (idx != -1) _slots[idx] = null;
    });
  }

  // ── WebSocket event handler ───────────────────────────────────
  void _onServerMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null) return;
=======
  void openSkillDialog() {
    if (currentRoleSkills.length < 2) return;

    final s1 = currentRoleSkills[0];
    final s2 = currentRoleSkills[1];
>>>>>>> 06601c709c9d8c44475a7097969fb5f815969cca

    switch (type) {
      case 'room.state':
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          final room = RoomModel.fromJson(payload);
          _applyRoomPlayers(room.players);
        }
        break;

      case 'room.player_joined':
        final p = msg['payload'];
        final username = p?['username'] as String? ?? 'Player';
        final playerId = p?['playerId'] as String? ?? '';
        _addPlayer(username, playerId);
        break;

      case 'room.player_left':
        final p = msg['payload'];
        final username = p?['username'] as String? ?? '';
        if (username.isNotEmpty) _removePlayer(username);
        break;
    }
  }

  // ── Build players list for the grid widgets ───────────────────
  List<PlayerModel> get _playerModels => List.generate(16, (i) {
        return PlayerModel(
          number: i + 1,
          name: _slots[i] ?? '',   // empty string = vacant slot
        );
      });

  // ── UI helpers ────────────────────────────────────────────────
  void openPlayersPopup() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
<<<<<<< HEAD
      builder: (_) => PlayersPopup(
        players: _slots
            .asMap()
            .entries
            .where((e) => e.value != null)
            .map((e) => 'ห้อง${e.key + 1} ${e.value}')
            .toList(),
      ),
    );
  }

  void onPlayerTap(int number) {
    if (number == (mySlot ?? -1)) return;
    setState(() => selectedTarget = number);
  }

  void openSkillDialog() {
    if (currentRoleSkills.length < 2) return;
    final skill1 = currentRoleSkills[0];
    final skill2 = currentRoleSkills[1];
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => SkillPopupChoice(
        skill1Name: skill1.name,
        skill1Image: skill1.image,
        skill2Name: skill2.name,
        skill2Image: skill2.image,
        onSkill1: () { Navigator.pop(context); debugPrint('Skill: ${skill1.name}'); },
        onSkill2: () { Navigator.pop(context); debugPrint('Skill: ${skill2.name}'); },
        onClose:  () { Navigator.pop(context); },
=======
      builder: (_) => SkillPopupChoice(
        skill1Name: s1.name,
        skill1Description: s1.description,
        skill1Image: s1.image,
        skill2Name: s2.name,
        skill2Description: s2.description,
        skill2Image: s2.image,
        onSkill1: () {
          Navigator.pop(context);
          showDialog(
            context: context,
            barrierColor: Colors.black54,
            builder: (_) => SkillPopupResult(
              skillName: s1.name,
              skillImage: s1.image,
              resultMessage: '1 น้องข้าว หมายเลขฝ่าย\n“ผี”',
            ),
          );
        },
        onSkill2: () {
          Navigator.pop(context);
          showDialog(
            context: context,
            barrierColor: Colors.black54,
            builder: (_) => SkillPopupResult(
              skillName: s2.name,
              skillImage: s2.image,
              resultMessage: 'ชุบชีวิตผู้เล่นสำเร็จ',
            ),
          );
        },
        onClose: () => Navigator.pop(context),
>>>>>>> 06601c709c9d8c44475a7097969fb5f815969cca
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final players = _playerModels;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          width: 390,
          height: screenH > 844 ? 844 : screenH,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              /// Background
              Positioned.fill(
                child: Image.asset(
                  isDay ? 'assets/images/DayTimeBg.jpg' : 'assets/images/NightTimeBg.jpg',
                  fit: BoxFit.cover,
                ),
              ),

              /// Main UI
              Positioned.fill(
                child: Column(
                  children: [
                    /// Top Bar
                    GameTopBar(
                      title: isDay ? 'รอผู้เล่น...' : 'เวลากลางคืน',
                      onExitTap: () => showDialog(
                        context: context,
                        builder: (_) => const ExitGamePopup(),
                      ),
                      onPlayerTap: openPlayersPopup,
                    ),

                    const SizedBox(height: 6),

                    /// Player Grid (16 fixed slots)
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: isDay
                            ? PlayerGridDay(
                                players: players,
                                myPlayerNumber: mySlot ?? 0,
                                selectedTarget: selectedTarget,
                                isVotePhase: false,
                                onPlayerTap: onPlayerTap,
                              )
                            : PlayerGridNight(
                                players: players,
                                myPlayerNumber: mySlot ?? 0,
                                selectedTarget: selectedTarget,
                                isVotePhase: false,
                                onPlayerTap: onPlayerTap,
                              ),
                      ),
                    ),

                    const SizedBox(height: 2),

                    /// Chat Box
                    SizedBox(
                      height: 220,
                      child: ChatBox(messages: chatMessages),
                    ),

                    const SizedBox(height: 4),

                    /// Chat Input
                    ChatInputRow(
                      onRoleInfoTap: () => showDialog(
                        context: context,
                        builder: (_) => RolesDialog(),
                      ),
                      onSkillTap: openSkillDialog,
                      onSend: (msg) => debugPrint('Send: $msg'),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),

              /// Day Animation
              if (isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: DayTimeAnimation()),
                  ),
                ),

              /// Night Animation
              if (!isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(child: NightTimeAnimation()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}