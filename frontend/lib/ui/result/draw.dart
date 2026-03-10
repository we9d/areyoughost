import 'package:areyoughost/ui/result/result_screen_template.dart';
import 'package:flutter/material.dart';

class DrawScreen extends StatelessWidget {
  const DrawScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResultScreenTemplate(
      imagePath: 'assets/images/draw.png',
    );
  }
}