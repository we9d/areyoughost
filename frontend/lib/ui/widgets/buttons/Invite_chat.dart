import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/icons/sent_message_icons.dart';

class InviteChat extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const InviteChat({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E9E9),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [

          /// ช่องพิมพ์ข้อความ
          Expanded(
            child: TextField(
              controller: controller,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(
                color: Colors.black,
              ),
              decoration: const InputDecoration(
                hintText: "ส่งข้อความ",
                hintStyle: TextStyle(
                  color: Color(0xFF444444),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),

          /// ปุ่มส่ง
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            mouseCursor: SystemMouseCursors.click,
            onPressed: onSend,
            icon: const SendIcon(
              size: 20,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}