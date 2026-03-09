import 'package:flutter/material.dart';

class PlayerCharacter extends StatelessWidget {
  const PlayerCharacter({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 3, // ระยะจากล่าง
      right: 0,  // ระยะจากขวา
      child: Image.asset(
        "assets/images/Character.png",
        width: 25,   // ปรับขนาดตัวละคร
        height: 25,
        fit: BoxFit.contain,
      ),
    );
  }
}

