import 'package:flutter/material.dart';

class GhostHand extends StatelessWidget {
  final int number;
  final Color numberColor;

  const GhostHand({
    super.key,
    required this.number,
    this.numberColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Image.asset(
          "assets/images/Ghost_Finger.png",
          width: 50,
        ),

        Positioned(
          top: 5.5,
          left: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              /// ขอบตัวเลข
              Text(
                "$number",
                style: TextStyle(
                  fontSize: 11,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = Colors.white,
                ),
              ),

              /// ตัวเลขจริง
              Text(
                "$number",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: numberColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}