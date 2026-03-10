/// Are You Ghost? - A desktop-first multiplayer social deduction game
///
/// This is the main entry point for the Flutter frontend application.
/// The app uses a mobile-like display (390x844) centered on desktop screens.
library;
import 'package:areyoughost/ui/result/draw.dart';
import 'package:areyoughost/ui/result/ghosts-defeat.dart';
import 'package:areyoughost/ui/result/ghosts-win.dart';
import 'package:areyoughost/ui/result/serialkiller-defeat.dart';
import 'package:areyoughost/ui/result/serialkiller-win.dart';
import 'package:areyoughost/ui/result/spirit-defeat.dart';
import 'package:areyoughost/ui/result/villagers-defeat.dart';
import 'package:areyoughost/ui/result/villagers-win.dart';
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
 // Initialize Rust API (Database, etc.)
  // This also initializes RustLib internally

  // Check login status
  await AuthService.checkLoginStatus();

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const double phoneWidth = 390;
  const double phoneHeight = 844;

  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(phoneWidth, phoneHeight),
    center: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

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
      home: const HomeScreen(),
    );
  }
}
