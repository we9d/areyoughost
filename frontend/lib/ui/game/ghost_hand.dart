import 'package:flutter/material.dart';

class GhostHand extends StatelessWidget {
  final int number;
  const GhostHand({super.key, required this.number});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 35, // 👉 ขยับซ้าย-ขวา
      top: 25, // 👉 ขยับขึ้น-ลง
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            "assets/images/Ghost_Finger.png",
            width: 45, // 👉 ขยายขนาดมือ
          ),
          Positioned(
            top: 3.5,
            left: 14,
            child: Text(
              "$number",
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}