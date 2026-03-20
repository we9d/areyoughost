import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ChatInputRowRole extends StatefulWidget {
  final VoidCallback onRoleInfoTap;
  final ValueChanged<String> onSend;

  const ChatInputRowRole({
    super.key,
    required this.onRoleInfoTap,
    required this.onSend,
  });

  @override
  State<ChatInputRowRole> createState() => _ChatInputRowRoleState();
}

class _ChatInputRowRoleState extends State<ChatInputRowRole> {
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

            /// ROLE ICON
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

            const SizedBox(width: 10),

            /// INPUT
            Expanded(
              child: _buildInput(),
            ),
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
          hintStyle: TextStyle(
            color: Colors.grey,
            fontSize: 17,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.only(bottom: 8),
        ),
      ),
    );
  }
}