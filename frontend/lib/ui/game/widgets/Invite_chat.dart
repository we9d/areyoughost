import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const ChatInput({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 50,

      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        borderRadius: BorderRadius.circular(25),
      ),

      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "ส่งข้อความ",
                border: InputBorder.none,
              ),
            ),
          ),

          GestureDetector(
            onTap: onSend,
            child: const Icon(
              Icons.send,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}