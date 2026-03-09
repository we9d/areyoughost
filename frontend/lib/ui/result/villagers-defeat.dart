import 'package:flutter/material.dart';
import 'package:areyoughost/ui/result/result_screen_template.dart';

class VillagersDefeatScreen extends StatelessWidget {
  const VillagersDefeatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResultScreenTemplate(
      imagePath: 'assets/images/villagers-defeat.png',
    );
  }
}