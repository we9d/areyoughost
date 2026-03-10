/// Are You Ghost? - A desktop-first multiplayer social deduction game
///
/// This is the main entry point for the Flutter frontend application.
/// The app uses a mobile-like display (390x844) centered on desktop screens.
library;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:areyoughost/theme/app_theme.dart';
// removed unused import of GameScreen to avoid unresolved URI during analysis
import 'package:areyoughost/ui/widgets/mobile_wrapper.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/ui/home/home.dart';
import 'package:areyoughost/services/rust_api.dart';
import 'package:areyoughost/ui/game/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await AuthService.checkLoginStatus();

  runApp(const AreYouGhostApp());
}

/// Main application widget
class AreYouGhostApp extends StatelessWidget {
  const AreYouGhostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghostปะคะ?',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // theme: ThemeData(fontFamily: 'Charmonman'),
      builder: (context, child) {
        return MobileWrapper(child: child!);
      },
       home: const GameScreen(
        roomId: "demo_room",
      ),
    );
  }
}
