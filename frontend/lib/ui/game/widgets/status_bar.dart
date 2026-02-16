import 'package:flutter/material.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.centerRight,
      child: const Text('เล่นต่อแล้ว • ไม่ใช่ตอน', style: TextStyle(color: Colors.white70)),
    );
  }
}
