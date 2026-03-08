import 'package:flutter/material.dart';

class FriendStatusList extends StatelessWidget {
  const FriendStatusList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FriendStatusItem(
          color: const Color(0xFF018A0C),
          name: "น้องข้าวพาเพลิน",
          status: "เข้าร่วม",
        ),
        const SizedBox(height: 8),
        const FriendStatusItem(
          color: Colors.red,
          name: "น้องบูม",
          status: "รอการตอบรับ",
        ),
      ],
    );
  }
}

class FriendStatusItem extends StatelessWidget {
  final Color color;
  final String name;
  final String status;

  const FriendStatusItem({
    super.key,
    required this.color,
    required this.name,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        /// จุดสถานะ
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 8),

        /// ชื่อ
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              decorationColor: Colors.black,
              color: Colors.black,
            ),
          ),
        ),

        Text(
          status,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}