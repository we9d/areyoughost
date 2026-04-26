import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:flutter/material.dart';

class AcceptInviteButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const AcceptInviteButton({
    super.key,
    required this.onPressed,
    this.label = 'ยอมรับ',
  });

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: 46,
      width: 114,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.fromARGB(255, 189, 154, 56),
          Color(0xFFE7C66A),
        ],
        stops: [0.0, 1.5],
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}