import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';

class StartButton extends StatelessWidget {
  final VoidCallback onPressed;
  const StartButton({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Shadow(
        height: 60,
        width: 150,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF9C7F2E),
            Color(0xFFE7C66A),
          ],
          stops: [0.0, 1.5],
        ),
        onPressed: onPressed,
        child: const Text(
          "เริ่มเกม",
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
