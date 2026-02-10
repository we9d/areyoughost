import 'package:flutter/material.dart';

class SettingsTitle extends StatelessWidget {
  const SettingsTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: const Text(
          'การตั้งค่า',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline,
            decorationThickness: 2,
            decorationColor: Colors.black,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
