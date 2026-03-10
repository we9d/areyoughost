import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';

class StartGameButton extends StatelessWidget {
  final VoidCallback onPressed;

  const StartGameButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Shadow(
        height: 40,
        width: 315,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF9C7F2E), Color(0xFFE7C66A)
          ],
          stops: [0.0, 1],
        ),
        onPressed: onPressed,
        child: const Padding(
          padding: EdgeInsets.only(top: 11),
          child: Text(
            "เริ่มเกม",
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}