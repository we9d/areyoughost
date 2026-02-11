import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';

/// A custom button with inner shadow effect used throughout the authentication flow.
/// 
/// This button matches the shadow and gradient styling used on the main screen.
class AuthButton extends StatelessWidget {
  /// The text to display on the button
  final String text;
  
  /// Callback function when the button is tapped
  final VoidCallback onTap;
  
  /// Optional custom width (defaults to 172)
  final double? width;
  
  /// Optional custom height (defaults to 40)
  final double? height;

  const AuthButton({
    super.key,
    required this.text,
    required this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Shadow(
      height: height ?? 40,
      width: width ?? 172,
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.fromARGB(255, 189, 154, 56), Color(0xFFE7C66A)],
        stops: [0.0, 1.5],
      ),
      onPressed: onTap,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Charmonman',
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }
}
