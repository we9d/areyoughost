import 'package:flutter/material.dart';
import 'package:areyoughost/ui/home/home.dart';
import 'package:areyoughost/ui/widgets/buttons/back_home_button.dart';

class ResultScreenTemplate extends StatelessWidget {
  final String imagePath;

  const ResultScreenTemplate({super.key, required this.imagePath});

  void _goHome(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double designWidth = 390;
            const double designHeight = 844;

            return SizedBox(
              width: designWidth,
              height: designHeight,
              child: Stack(
                children: [
                  Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    width: designWidth,
                    height: designHeight,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 34,
                    child: Center(
                      child: BackHomeButton(onPressed: () => _goHome(context)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
