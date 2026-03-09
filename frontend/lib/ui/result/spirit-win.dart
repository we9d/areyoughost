import 'package:flutter/material.dart';
import 'package:areyoughost/ui/result/result_screen_template.dart';

class SpiritWinScreen extends StatelessWidget {
  const SpiritWinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResultScreenTemplate(
      imagePath: 'assets/images/spirit-win.png',
    );
  }
}