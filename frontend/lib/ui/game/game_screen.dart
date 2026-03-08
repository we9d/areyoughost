import 'package:flutter/material.dart';
import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/player_grid.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';
import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';
import 'package:areyoughost/ui/dialogs/skill_select_dialog.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/game/widgets/DayTimeAnimation.dart';

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
  late List<RoleInfo> allRoles;
  late List<SkillOption> currentRoleSkills;

  int myPlayerNumber = 7;
  int? selectedTarget;

  @override
  void initState() {
    super.initState();

    players = List.generate(
      16,
      (i) => PlayerModel(number: i + 1, name: 'Player'),
    );

    chatMessages = [];

    allRoles = [
      RoleInfo(name: 'Villager', description: 'A simple villager'),
    ];

    currentRoleSkills = [
      SkillOption(
        name: 'Investigate',
        description: 'Investigate a player',
      ),
      SkillOption(
        name: 'Protect',
        description: 'Protect a player',
      ),
    ];
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
                  'assets/images/NightTimeBg.jpg',
                  fit: BoxFit.cover,
                ),
              ),

              /// ☀️ Sun Animation (Moved to front below Main UI)

              /// Main UI
              Positioned.fill(
                child: Column(
                  children: [

                    /// Top Bar
                    GameTopBar(
                      title: 'เวลากลางคืน 20 วินาที',
                      onExitTap: () {},
                      onPlayerTap: () {},
                    ),

                    const SizedBox(height: 6),

                    /// Player Grid
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: PlayerGrid(
                          players: players,
                          myPlayerNumber: myPlayerNumber,
                          selectedTarget: selectedTarget,
                          onPlayerTap: (number) {

                            if (number == myPlayerNumber) return;

                            setState(() {
                              selectedTarget = number;
                            });

                          },
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
                          builder: (_) => RoleInfoDialog(
                            roles: allRoles,
                          ),
                        );
                      },
                      onSkillTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => SkillSelectDialog(
                            skills: currentRoleSkills,
                            onSelect: (_) {},
                          ),
                        );
                      },
                      onSend: (_) {},
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),

              /// ☀️ Sun Animation
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                right: 0,
                child: const IgnorePointer(
                  child: Center(
                    child: DayTimeAnimation(),
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