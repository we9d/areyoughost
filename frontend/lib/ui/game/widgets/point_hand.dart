import 'package:flutter/material.dart';

class PointHand extends StatelessWidget {
  final int number;

  const PointHand({
    super.key,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.asset(
          "assets/images/Point_Finger.png",
          width: 45,
        ),

        Positioned(
          top: 0,
          left: 15,
          child: Stack(
            alignment: Alignment.center,
            children: [
              /// ขอบตัวเลข
              Text(
                "$number",
                style: TextStyle(
                  fontSize: 13,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = Colors.white,
                ),
              ),

              /// ตัวเลขจริง
              Text(
                "$number",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}