import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:flutter/material.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: 50,
      width: 150,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.fromARGB(255, 119, 41, 41), Color(0xFFC0392B)],
        stops: [0.0, 1.5],
      ),
      onPressed: () => Navigator.pop(context), //  ปิด popup
      child: const Text(
        "ออกจากระบบ",
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
