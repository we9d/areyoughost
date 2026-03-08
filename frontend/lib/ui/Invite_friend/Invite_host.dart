import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:areyoughost/ui/widgets/buttons/start_game_buttons.dart';
import 'package:areyoughost/ui/widgets/buttons/Invite_button.dart';
import 'package:areyoughost/ui/widgets/buttons/Invite_chat.dart';
import 'package:areyoughost/ui/game/random_role_screen.dart';
import 'package:areyoughost/ui/widgets/message.dart';

class InviteFriendScreen extends StatefulWidget {
  const InviteFriendScreen({super.key});

  @override
  State<InviteFriendScreen> createState() => _InviteFriendScreenState();
}

class _InviteFriendScreenState extends State<InviteFriendScreen> {
  final TextEditingController messageController = TextEditingController();

  void sendMessage() {
    if (messageController.text.isNotEmpty) {
      print(messageController.text);
      messageController.clear();
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double designWidth = 390;
    const double designHeight = 844;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: designWidth,
          height: designHeight,
          child: Stack(
            children: [
              /// Background
              Image.asset(
                'assets/images/InvitePage.jpg',
                fit: BoxFit.cover,
                width: designWidth,
                height: designHeight,
              ),

              const Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    "ยินดีต้อนรับเข้าสู่เกมใหม่ Ghost ป่ะคะ?",
                    style: TextStyle(
                      color: Color(0xFFF1C232),
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              /// Message
              const Positioned(
                top: 100,
                left: 30,
                right: 20,
                child: Message(),
              ),

              /// ปุ่มย้อนกลับ
              Positioned(
                top: 40,
                left: 8,
                child: IconButton(
                  icon: Icon(
                    PhosphorIcons.caretLeft(),
                    color: Colors.white,
                    size: 32,
                  ),
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ),

              /// ปุ่ม Start Game
              Positioned(
                top: 615,
                left: 0,
                right: 0,
                child: Center(
                  child: StartGameButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RandomRoleScreen(roomId: 'invite_host'),
                        ),
                      );
                    },
                  ),
                ),
              ),

              /// ปุ่ม Invite Friend
              Positioned(
                top: 668, 
                left: 0,
                right: 0,
                child: const Center(
                  child: InviteButton(),
                ),
              ),

              /// ช่องส่งข้อความ
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: InviteChat(
                  controller: messageController,
                  onSend: sendMessage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}