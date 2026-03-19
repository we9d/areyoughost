import 'package:flutter/material.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/widgets/buttons/roles_buttons.dart';
import 'package:areyoughost/ui/dialogs/skill_select_dialog.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/game/widgets/DayTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/NightTimeAnimation.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_day.dart';
import 'package:areyoughost/ui/game/widgets/player_grid_night.dart';
import 'package:areyoughost/ui/game/widgets/players_popup.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_choice.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';
import 'package:areyoughost/ui/game/widgets/players_popup.dart';
import 'package:areyoughost/ui/game/widgets/exit_game_popup.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';

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
  bool isDay = true;

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

    /// ROLE SKILLS (MOCK)

    currentRoleSkills = [
      SkillOption(
        name: 'Investigate',
        description: 'Investigate a player',
        image: 'assets/icons/investigate.png',
      ),
      SkillOption(
        name: 'Protect',
        description: 'Protect a player',
        image: 'assets/icons/protect.png',
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


  void onPlayerTap(int number) {
    if (number == myPlayerNumber) return;

    setState(() {
      selectedTarget = number;
    });
  }

  void openSkillDialog() {

    if (currentRoleSkills.length < 2) return;

    final skill1 = currentRoleSkills[0];
    final skill2 = currentRoleSkills[1];

    showDialog(
      context: context,
      barrierColor: Colors.black54,

      builder: (_) {

        return SkillPopupChoice(

          skill1Name: skill1.name,
          skill1Description: skill1.description,
          skill1Image: skill1.image,

          skill2Name: skill2.name,
          skill2Description: skill2.description,
          skill2Image: skill2.image,

          onSkill1: () {

            Navigator.pop(context);

            /// BACKEND EVENT
            ///
            /// socket.emit("useSkill", {
            ///   "roomId": widget.roomId,
            ///   "skill": skill1.name
            /// });

            debugPrint("Skill selected: ${skill1.name}");
          },

          onSkill2: () {

            Navigator.pop(context);

            /// BACKEND EVENT
            ///
            /// socket.emit("useSkill", {
            ///   "roomId": widget.roomId,
            ///   "skill": skill2.name
            /// });

            debugPrint("Skill selected: ${skill2.name}");
          },

          onClose: () {
            Navigator.pop(context);
          },
        );
      },
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
                            },                      onPlayerTap: openPlayersPopup,
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

                    /// Chat Input
                    ChatInputRow(
                      onRoleInfoTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => const RolesDialog(),
                        );
                      },
                      onSkillTap: openSkillDialog,
                      onSend: (_) {},
                    ),

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