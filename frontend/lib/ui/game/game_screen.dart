import 'package:flutter/material.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/player_grid.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_day.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_night.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';

import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';

import 'package:areyoughost/models/mock_models.dart';

import 'package:areyoughost/ui/game/widgets/players_popup.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';

/// ===============================================================
/// GAME SCREEN
/// ---------------------------------------------------------------
/// หน้าหลักของเกมระหว่างเล่น
///
/// Layout:
/// TopBar
/// PlayerGrid
/// ChatBox
/// ChatInputRow
///
/// NOTE FOR BACKEND TEAM
/// หน้านี้เป็น UI Container เท่านั้น
///
/// ข้อมูลจริงจะมาจาก
/// - WebSocket
/// - Game State Server
/// ===============================================================

class GameScreen extends StatefulWidget {

  /// room id ของเกม
  final String roomId;

  /// role ของ player (backend จะส่งมาหลังเริ่มเกม)
  final String? role;

  const GameScreen({
    super.key,
    required this.roomId,
    this.role,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {

  /// ===============================================================
  /// TEMP GAME STATE (MOCK)
  /// ===============================================================

  late List<PlayerModel> players;

  late List<ChatMessage> chatMessages;

  late List<RoleInfo> allRoles;

  /// skill list ของ role ปัจจุบัน
  /// ใช้ Map แทน model ชั่วคราว

  late List<Map<String, String>> currentRoleSkills;

  /// ===============================================================
  /// INIT STATE
  /// ===============================================================

  @override
  void initState() {
    super.initState();

    /// MOCK PLAYERS

    players = List.generate(
      16,
      (i) => PlayerModel(
        number: i + 1,
        name: 'Player',
      ),
    );

    /// CHAT LIST

    chatMessages = [];

    /// ROLE INFO

    allRoles = [
      RoleInfo(
        name: 'Villager',
        description: 'A simple villager',
      ),
    ];

    /// ROLE SKILLS (MOCK)

    currentRoleSkills = [

      {
        "name": "Investigate",
        "image": "assets/icons/investigate.png",
      },

      {
        "name": "Protect",
        "image": "assets/icons/protect.png",
      },

    ];
  }

  /// ===============================================================
  /// PLAYERS POPUP
  /// ===============================================================

  void openPlayersPopup() {

    showDialog(
      context: context,
      barrierColor: Colors.black54,

      builder: (_) {

        return PlayersPopup(
          players: players
              .map((p) => "ห้อง${p.number} ${p.name}")
              .toList(),
        );
      },
    );
  }

  /// ===============================================================
  /// SKILL POPUP
  /// ===============================================================

  void openSkillDialog() {

    if (currentRoleSkills.length < 2) return;

    final skill1 = currentRoleSkills[0];
    final skill2 = currentRoleSkills[1];

    showDialog(
      context: context,
      barrierColor: Colors.black54,

      builder: (_) {

        return SkillPopupChoice(

          skill1Name: skill1["name"]!,
          skill1Image: skill1["image"]!,

          skill2Name: skill2["name"]!,
          skill2Image: skill2["image"]!,

          onSkill1: () {

            Navigator.pop(context);

            /// BACKEND EVENT
            ///
            /// socket.emit("useSkill", {
            ///   "roomId": widget.roomId,
            ///   "skill": skill1["name"]
            /// });

            debugPrint("Skill selected: ${skill1["name"]}");
          },

          onSkill2: () {

            Navigator.pop(context);

            /// BACKEND EVENT
            ///
            /// socket.emit("useSkill", {
            ///   "roomId": widget.roomId,
            ///   "skill": skill2["name"]
            /// });

            debugPrint("Skill selected: ${skill2["name"]}");
          },

          onClose: () {
            Navigator.pop(context);
          },
        );
      },
    );
  }

  /// ===============================================================
  /// BUILD
  /// ===============================================================

  @override
  Widget build(BuildContext context) {

    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(

      backgroundColor: Colors.black,

      body: SafeArea(

        child: Center(

          /// จำกัด width ให้เหมือนมือถือ

          child: ConstrainedBox(

            constraints: const BoxConstraints(
              maxWidth: 390,
            ),

            child: SizedBox(

              height: screenH > 844 ? 844 : screenH,

              child: Container(

                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                ),

                clipBehavior: Clip.hardEdge,

                child: Stack(

                  children: [

                    /// BACKGROUND IMAGE

                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/NightTimeBg.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),

                    /// MAIN GAME UI

                    Positioned.fill(

                      child: Column(

                        children: [

                          /// TOP BAR

                          GameTopBar(

                            title: "เวลากลางคืน 20 วินาที",

                            onExitTap: () {

                              showDialog(
                                context: context,
                                builder: (_) => const ExitGamePopup(),
                              );
                            },

                            onPlayerTap: openPlayersPopup,
                          ),

                          const SizedBox(height: 6),

                          /// PLAYER GRID

                          Expanded(
                            flex: 5,

                            child: Padding(

                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),

                              child: PlayerGrid(
                                players: players,
                              ),
                            ),
                          ),

                          const SizedBox(height: 4),

                          /// CHAT BOX

                          Flexible(
                            flex: 3,

                            child: ChatBox(
                              messages: chatMessages,
                            ),
                          ),

                          const SizedBox(height: 4),

                          /// CHAT INPUT

                          ChatInputRow(

                            /// ROLE INFO POPUP

                            onRoleInfoTap: () {

                              showDialog(
                                context: context,

                                builder: (_) {

                                  return RoleInfoDialog(
                                    roles: allRoles,
                                  );
                                },
                              );
                            },

                            /// SKILL POPUP

                            onSkillTap: openSkillDialog,

                            /// SEND CHAT MESSAGE

                            onSend: (message) {

                              /// BACKEND CHAT EVENT
                              ///
                              /// socket.emit("sendMessage", {
                              ///   "roomId": widget.roomId,
                              ///   "message": message
                              /// });

                              debugPrint("Send message: $message");
                            },
                          ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}