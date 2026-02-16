import 'package:flutter/material.dart';

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
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            /// 🔹 บทบาท
            IconButton(
              icon: const Icon(Icons.masks),
              color: Colors.white,
              splashRadius: 20,
              onPressed: widget.onRoleInfoTap,
            ),

            /// 🔹 แชท (icon กลาง)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              color: Colors.white,
              splashRadius: 20,
              onPressed: () {},
            ),

            /// 🔹 สกิล
            IconButton(
              icon: const Icon(Icons.flash_on),
              color: Colors.white,
              splashRadius: 20,
              onPressed: widget.onSkillTap,
            ),

            const SizedBox(width: 6),

            /// 🔹 Input box
            Expanded(
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: 'ส่งข้อความ', // ✅ ตามที่ขอ
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: Colors.black38,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
