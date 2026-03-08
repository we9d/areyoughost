import 'package:flutter/material.dart';

class PlayerSign extends StatelessWidget {
  final int number;

  const PlayerSign({
    super.key,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: -8.5,
      left: 2.5,
      right: 0,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            /// ป้ายไม้
            Image.asset(
              "assets/images/Sign.png",
              width: 180,
            ),

            /// ตัวเลข
            Transform.translate(
              offset: const Offset(-2, -0.5), // <--- ขยับแกน X (ซ้าย-) และ แกน Y (ลง+)
              child: Text(
                "$number",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}