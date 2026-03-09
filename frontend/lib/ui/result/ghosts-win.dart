import 'package:flutter/material.dart';
import 'package:areyoughost/ui/result/result_screen_template.dart';

class GhostsWinScreen extends StatelessWidget {
  const GhostsWinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResultScreenTemplate(
      imagePath: 'assets/images/ghosts-win.png',
    );
  }
}