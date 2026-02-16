import 'package:flutter/material.dart';

import 'package:areyoughost/ui/game/widgets/game_top_bar.dart';
import 'package:areyoughost/ui/game/widgets/player_grid.dart';
import 'package:areyoughost/ui/game/widgets/chat_box.dart';
import 'package:areyoughost/ui/game/widgets/chat_input_row.dart';

import 'package:areyoughost/ui/dialogs/role_info_dialog.dart';
import 'package:areyoughost/ui/dialogs/skill_select_dialog.dart';

import 'package:areyoughost/models/mock_models.dart';

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

  @override
  void initState() {
    super.initState();

    players = List.generate(
      16,
      (i) => PlayerModel(
        number: i + 1,
        name: 'Player',
      ),
    );

    chatMessages = [
      ChatMessage(
        messageId: '1',
        senderId: '1',
        senderName: 'Player 1',
        message: 'Hello!',
        phaseType: 'night',
        createdAt: DateTime.now(),
      ),
    ];

    allRoles = [
      RoleInfo(
        name: 'Villager',
        description: 'A simple villager',
      ),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/NightTimeBg.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: Column(
            children: [
              /// 🔹 TOP BAR
              GameTopBar(
                title: 'เวลากลางคืน 20 วินาที',
                onExitTap: () {},
                onPlayerTap: () {},
              ),

              const SizedBox(height: 8),

              /// 🔹 PLAYER GRID
              PlayerGrid(players: players),

              const SizedBox(height: 8),

              /// 🔹 CHAT BOX
              Expanded(
                child: ChatBox(messages: chatMessages),
              ),

              const SizedBox(height: 4),

              /// 🔹 CHAT INPUT
              ChatInputRow(
                onRoleInfoTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => RoleInfoDialog(roles: allRoles),
                  );
                },
                onSkillTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => SkillSelectDialog(
                      skills: currentRoleSkills,
                      onSelect: (skill) {},
                    ),
                  );
                },
                onSend: (text) {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
