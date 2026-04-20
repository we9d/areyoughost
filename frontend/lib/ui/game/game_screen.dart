import 'package:flutter/material.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_role.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_role_skill.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_full.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row_role_chat.dart';
import 'package:areyoughost/ui/widgets/buttons/roles_buttons.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/game/widgets/DayTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/NightTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_day.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_night.dart';
import 'package:areyoughost/ui/game/widgets/players_popup.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_result.dart';
// import 'package:areyoughost/ui/game/dialogs/skill_popup_single.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
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
  late List<PlayerModel> players;
  late List<ChatMessage> chatMessages;
  late List<SkillOption> currentRoleSkills;
  
  late List<RoleInfo> allRoles;
 // late List<Map<String, String>> currentRoleSkills;
  int myPlayerNumber = 7;
  int? selectedTarget;

  /// 🌞 Day / 🌙 Night
  bool isDay = false;

  @override
  void initState() {
    super.initState();

    players = List.generate(
      16,
      (i) => PlayerModel(number: i + 1, name: 'Player'),
    );

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


  void onPlayerTap(int number) {
    if (number == myPlayerNumber) return;

    setState(() {
      selectedTarget = number;
    });
  }

  void openSkillDialog() {
    if (currentRoleSkills.length < 2) return;

    final s1 = currentRoleSkills[0];
    final s2 = currentRoleSkills[1];

    showDialog(
      context: context,
      barrierColor: Colors.black54,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

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
                  isDay
                      ? 'assets/images/DayTimeBg.jpg'
                      : 'assets/images/NightTimeBg.jpg',
                  fit: BoxFit.cover,
                ),
              ),

              /// Main UI
              Positioned.fill(
                child: Column(
                  children: [

                    /// Top Bar
                    GameTopBar(
                      title: isDay
                          ? 'เวลากลางวัน 20 วินาที'
                          : 'เวลากลางคืน 20 วินาที',
                     onExitTap: () {

                              showDialog(
                                context: context,
                                builder: (_) => const ExitGamePopup(),
                              );
                            },                      
                      onPlayerTap: openPlayersPopup,
                    ),

                    const SizedBox(height: 6),

                    /// Player Grid
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: isDay
                            ? PlayerGridDay(
                                players: players,
                                myPlayerNumber: myPlayerNumber,
                                selectedTarget: selectedTarget,
                                isVotePhase: true,
                                onPlayerTap: onPlayerTap,
                              )
                            : PlayerGridNight(
                                players: players,
                                myPlayerNumber: myPlayerNumber,
                                selectedTarget: selectedTarget,
                                isVotePhase: true,
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

                    /// CHAT INPUT SECTION
                    isDay
                        ? (currentRoleSkills.isNotEmpty
                            ? ChatInputRowRoleSkill(
                                onRoleInfoTap: () => _handleRoleInfoTap(context),
                                onSend: (text) => _handleSendMessage(text),
                              )
                            : ChatInputRowRole(
                                onRoleInfoTap: () => _handleRoleInfoTap(context),
                                onSend: (text) => _handleSendMessage(text),
                              ))
                        : (currentRoleSkills.isNotEmpty
                            ? ChatInputRowFull(
                                onRoleInfoTap: () => _handleRoleInfoTap(context),
                                onSend: (text) => _handleSendMessage(text),
                              )
                            : ChatInputRowRoleChat(
                                onRoleInfoTap: () => _handleRoleInfoTap(context),
                                onSend: (text) => _handleSendMessage(text),
                              )),

                    const SizedBox(height: 10),
                  ],
                ),
              ),

              /// 🌞 Day Animation
              if (isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: DayTimeAnimation(),
                    ),
                  ),
                ),

              /// 🌙 Night Animation
              if (!isDay)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: NightTimeAnimation(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}