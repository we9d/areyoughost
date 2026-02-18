import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';

class PlaynowButton extends StatelessWidget {
  final VoidCallback onPressed;

  const PlaynowButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: 60,
      width: 150, // ให้เท่ากับ design
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1F3449),
          Color(0xFF3A5A7A),
        ],
        stops: [0.0, 1.5],
      ),
      onPressed: onPressed,
      child: const Text(
        "เล่นทันที",
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
