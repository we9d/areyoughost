import 'package:flutter/material.dart';

class PointHand extends StatelessWidget {
  final int number;
  const PointHand({super.key, required this.number});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 35, // 👉 ขยับซ้าย-ขวา
      top: 25, // 👉 ขยับขึ้น-ลง
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            "assets/images/Point_Finger.png",
            width: 45, // 👉 ขยายขนาดมือ
          ),
          Positioned(
            top: 1,
            left: 16,
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