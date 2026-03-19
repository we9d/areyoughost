import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';


import 'package:areyoughost/ui/game/dialogs/player_dead_popup.dart';
import 'package:areyoughost/ui/game/dialogs/skill_popup_single.dart';

class ChatInputRowFull extends StatefulWidget {
  final VoidCallback onRoleInfoTap;
  final ValueChanged<String> onSend;

  const ChatInputRowFull({
    super.key,
    required this.onRoleInfoTap,
    required this.onSend,
  });

  @override
  State<ChatInputRowFull> createState() => _ChatInputRowFullState();
}

class _ChatInputRowFullState extends State<ChatInputRowFull> {
  final TextEditingController _controller = TextEditingController();

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [

            /// ROLE
            IconButton(
              iconSize: 25,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                PhosphorIcons.maskHappy(),
                color: Colors.white,
              ),
              onPressed: widget.onRoleInfoTap,
            ),

            const SizedBox(width: 6),

            /// CHAT
            IconButton(
              iconSize: 25,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                PhosphorIcons.wechatLogo(),
                color: Colors.white,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const PlayerDeadPopup(),
                );
              },
            ),

            const SizedBox(width: 6),

            /// SKILL
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const SkillPopupSingle(),
                );
              },
              child: SvgPicture.asset(
                'assets/icons/skill-icon.svg',
                width: 25,
                height: 25,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(child: _buildInput()),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _handleSend(),
        decoration: const InputDecoration(
          hintText: "ส่งข้อความ",
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }
}