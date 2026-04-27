// Are You Ghost? — desktop-first multiplayer social deduction game.
// Entry point; uses a phone-sized viewport (390x844) centered on desktop.
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:areyoughost/theme/app_theme.dart';
// removed unused import of GameScreen to avoid unresolved URI during analysis
import 'package:areyoughost/ui/widgets/mobile_wrapper.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/services/rust_api.dart';
import 'package:areyoughost/services/ws_service.dart';
import 'package:areyoughost/services/invite_store.dart';
import 'package:areyoughost/ui/home/home.dart';

/// Root navigator — ใช้เชื่อม route หลัก (เช่น หลังรับคำเชิญจากไอคอนจดหมาย)
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Rust API (Database, etc.)
  // This also initializes RustLib internally.
  // In release distribution on friends' PCs, missing VC++/FFI deps can make
  // Rust init fail before Flutter renders anything. Keep app booting anyway.
  try {
    await RustApi.init();
  } catch (e) {
    debugPrint('Rust init skipped: $e');
  }

  // Check login status
  await AuthService.checkLoginStatus();
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
class AreYouGhostApp extends StatefulWidget {
  const AreYouGhostApp({super.key});

  @override
  State<AreYouGhostApp> createState() => _AreYouGhostAppState();
}

class _AreYouGhostAppState extends State<AreYouGhostApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen globally for invite.received events from any WS connection
    WsService.instance.stream.listen((msg) {
      if (msg['type'] == 'invite.received') {
        final payload = msg['payload'] as Map<String, dynamic>? ?? {};
        final invite = PendingInvite(
          inviteCode: payload['inviteCode'] as String? ?? '',
          fromPlayerId: payload['fromPlayerId'] as String? ?? '',
          fromUsername: payload['fromUsername'] as String? ?? 'เพื่อน',
        );
        if (invite.inviteCode.isEmpty) return;

        InviteStore.instance.add(invite);
        // ไม่เปิด popup อัตโนมัติ — ให้มีแค่จุดแดงที่ไอคอนจดหมาย ผู้เล่นกดเองแล้วค่อยเลือกรับ/ปฏิเสธ
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      WsService.instance.nudgeReconnectIfDisconnected();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Ghostปะคะ?',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // theme: ThemeData(fontFamily: 'Charmonman'),
      builder: (context, child) {
        return MobileWrapper(child: child!);
      },

      /// เปิดเกมตรงไปที่ GameScreen
      home: const HomeScreen(
      ),
    );
  }
}