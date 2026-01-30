import 'package:flutter/material.dart';
import 'package:areyoughost/theme/app_theme.dart';
import 'package:areyoughost/ui/login/login_screen.dart';
import 'package:areyoughost/ui/lobby/lobby_screen.dart';
import 'package:areyoughost/ui/game/game_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost Game',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LoginScreen(),
    );
  }
}
