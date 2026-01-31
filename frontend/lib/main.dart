/// Are You Ghost? - A desktop-first multiplayer social deduction game
/// 
/// This is the main entry point for the Flutter frontend application.
/// The app uses a mobile-like display (390x844) centered on desktop screens.
import 'package:flutter/material.dart';
import 'package:areyoughost/theme/app_theme.dart';
import 'package:areyoughost/ui/login/login_screen.dart';
import 'package:areyoughost/ui/lobby/lobby_screen.dart';
import 'package:areyoughost/ui/game/game_screen.dart';
import 'package:areyoughost/ui/widgets/mobile_wrapper.dart';

void main() {
  runApp(const AreYouGhostApp());
}

/// Main application widget
/// 
/// Configures the app with:
/// - Dark theme optimized for the ghost game aesthetic
/// - Mobile wrapper for desktop-centered display (390x844)
/// - Navigation to login screen as entry point
class AreYouGhostApp extends StatelessWidget {
  const AreYouGhostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Are You Ghost?',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        return MobileWrapper(child: child!);
      },
      home: const LoginScreen(),
    );
  }
}
