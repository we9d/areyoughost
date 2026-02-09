/// Are You Ghost? - A desktop-first multiplayer social deduction game
/// 
/// This is the main entry point for the Flutter frontend application.
/// The app uses a mobile-like display (390x844) centered on desktop screens.
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart'; // เพิ่ม
import 'package:areyoughost/theme/app_theme.dart';
import 'package:areyoughost/ui/login/login_screen.dart';
import 'package:areyoughost/ui/lobby/lobby_screen.dart';
import 'package:areyoughost/ui/game/game_screen.dart';
import 'package:areyoughost/ui/widgets/mobile_wrapper.dart';
import 'package:areyoughost/ui/home/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const double phoneWidth = 390;
  const double phoneHeight = 844;

  WindowOptions windowOptions = const WindowOptions(
    minimumSize: Size(phoneWidth, phoneHeight), // กำหนดขั้นต่ำ
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
