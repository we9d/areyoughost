import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:flutter/material.dart';

class RejectInviteButton extends StatelessWidget {
  final VoidCallback onPressed;

  const RejectInviteButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: 46,
      width: 114,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFC9C9C9), Color(0xFFE7E7E7)],
        stops: [0.0, 1.5],
      ),
      onPressed: onPressed,
      child: const Text(
        'ปฏิเสธ',
        style: TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
