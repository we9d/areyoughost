import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChatInputRow extends StatefulWidget {
  final VoidCallback onRoleInfoTap;
  final VoidCallback onSkillTap;
  final ValueChanged<String> onSend;

  const ChatInputRow({
    super.key,
    required this.onRoleInfoTap,
    required this.onSkillTap,
    required this.onSend,
  });

  @override
  State<ChatInputRow> createState() => _ChatInputRowState();
}

class _ChatInputRowState extends State<ChatInputRow> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56, // 👈 Reduced height
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), // 👈 Tighter padding
        child: Row(
          children: [
            /// 🔹 บทบาท
            IconButton(
              padding: const EdgeInsets.all(4), // 👈 Tighter spacing
              constraints: const BoxConstraints(), // 👈 No extra size
              icon: Icon(
                PhosphorIcons.maskHappy(),
                size: 25.0, // 👈 Size 25
                color: Colors.white,
              ),
              onPressed: widget.onRoleInfoTap,
            ),

            /// 🔹 แชท (icon กลาง)
            IconButton(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: Icon(
                PhosphorIcons.wechatLogo(),
                size: 25.0, // 👈 Size 25
                color: Colors.white,
              ),
              onPressed: () {},
            ),

            /// 🔹 สกิล
            GestureDetector(
              onTap: widget.onSkillTap,
              child: Container(
                width: 34, // 👈 Tighter
                height: 34,
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/icons/skill-icon.svg',
                  width: 25, // 👈 Size 25
                  height: 25,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8), // 👈 Balanced gap

            /// 🔹 Input box
            Expanded(
              child: Container(
                height: 36, // 👈 Slightly shorter box
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  textAlignVertical: TextAlignVertical.center, // 👈 Better alignment
                  decoration: const InputDecoration(
                    hintText: 'ส่งข้อความ',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: Colors.black38,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true, // 👈 Tighter layout
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
            
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
