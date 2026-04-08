/// Are You Ghost? - A desktop-first multiplayer social deduction game
///
/// This is the main entry point for the Flutter frontend application.
/// The app uses a mobile-like display (390x844) centered on desktop screens.
library;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:areyoughost/theme/app_theme.dart';
import 'package:areyoughost/ui/widgets/mobile_wrapper.dart';
import 'package:areyoughost/services/game_data_service.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/rust_api.dart';
import 'package:areyoughost/services/invite_store.dart';
import 'package:areyoughost/services/network_service.dart';
import 'package:areyoughost/ui/home/home.dart';
import 'package:areyoughost/models/invite_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Rust API bridge (Requirements 31.1, 31.2)
    await RustApi.init();
    
    // Initialize services that might fail if the server is unreachable
    await NetworkService().init();
    await AuthService.checkLoginStatus();
    await GameDataService.fetchGameData();
  } catch (e) {

    debugPrint('🚩 Initialization Warning (Continuing to UI): $e');
  }

  await windowManager.ensureInitialized();

  const double phoneWidth = 390;
  const double phoneHeight = 844;

  const WindowOptions windowOptions = WindowOptions(
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
class AreYouGhostApp extends StatefulWidget {
  const AreYouGhostApp({super.key});

  @override
  State<AreYouGhostApp> createState() => _AreYouGhostAppState();
}

class _AreYouGhostAppState extends State<AreYouGhostApp> {
  @override
  void initState() {
    super.initState();
    // TCP listeners will be implemented here for game state/invites
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghostปะคะ?',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        return MobileWrapper(child: child!);
      },
      home: const HomeScreen(
      ),
    );
  }
}