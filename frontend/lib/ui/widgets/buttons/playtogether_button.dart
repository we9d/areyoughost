import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';

class PlaytogetherButton extends StatelessWidget {
  final VoidCallback onPressed;

  const PlaytogetherButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: 60,
      width: 150,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF3A0F17),
          Color(0xFF6A1F2B),
        ],
        stops: [0.0, 1.5],
      ),
      onPressed: onPressed,
      child: const Text(
        "เล่นกับเพื่อน",
        style: TextStyle(
          color: Colors.white70,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
