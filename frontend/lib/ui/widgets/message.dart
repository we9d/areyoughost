import 'package:flutter/material.dart';

class Message extends StatelessWidget {
  const Message({super.key});

  Widget _buildMessageText(String text) {
    const String keyword = "เข้าร่วม";
    if (text.contains(keyword)) {
      final parts = text.split(keyword);
      List<TextSpan> spans = [];

      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          spans.add(TextSpan(text: parts[i]));
        }
        if (i < parts.length - 1) {
          spans.add(const TextSpan(
            text: keyword,
            style: TextStyle(
              color: Color(0xFF4DD6C9),
              fontWeight: FontWeight.bold,
            ),
          ));
        }
      }

      return Text.rich(
        TextSpan(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
          children: spans,
        ),
      );
    }

    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMessageText("2 น้องข้าวพาเพลิน เข้าร่วม"),
        const SizedBox(height: 10),
        _buildMessageText("2 น้องข้าวพาเพลิน Helloooooooooooooooooooooo"),
      ],
    );
  }
}