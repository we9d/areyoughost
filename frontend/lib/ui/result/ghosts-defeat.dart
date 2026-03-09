import 'package:flutter/material.dart';
import 'package:areyoughost/ui/result/result_screen_template.dart';

class GhostsDefeatScreen extends StatelessWidget {
  const GhostsDefeatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResultScreenTemplate(
      imagePath: 'assets/images/ghosts-defeat.png',
    );
  }
}