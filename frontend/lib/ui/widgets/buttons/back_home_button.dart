import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:flutter/material.dart';

class BackHomeButton extends StatelessWidget {
  final VoidCallback onPressed;

  const BackHomeButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: 50,
      width: 150,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.fromARGB(255, 189, 154, 56), Color(0xFFE7C66A)],
        stops: [0.0, 1.5],
      ),
      onPressed: onPressed,
      child: const Text(
        "กลับหน้าหลัก",
        style: TextStyle(
          color: Colors.black,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
