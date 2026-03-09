import 'package:flutter/material.dart';
import 'package:areyoughost/ui/result/result_screen_template.dart';

class VillagersWinScreen extends StatelessWidget {
  const VillagersWinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResultScreenTemplate(
      imagePath: 'assets/images/villagers-win.png',
    );
  }
}