import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

import 'package:areyoughost/ui/widgets/buttons/start_buttons.dart';
import 'package:areyoughost/ui/widgets/buttons/rules_buttons.dart';
import 'package:areyoughost/ui/widgets/icons/friend-icon.dart';
import 'package:areyoughost/ui/widgets/icons/mail_noti_icon.dart';
import 'package:areyoughost/ui/widgets/icons/setting-icon.dart';
import 'package:areyoughost/ui/widgets/roles_card.dart';
import 'package:areyoughost/ui/game/mode_select_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: LayoutBuilder(builder: (context, _) {
          const double w = 390;
          const double h = 844;
          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Image.asset('assets/images/mobileBg.jpg',
                    fit: BoxFit.cover, width: w, height: h),

                Positioned(
                  top: 48,
                  right: 10,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const MailNotiIcon(),
                    const SizedBox(width: 4),
                    AddFriendIcon(),
                    const SizedBox(width: 6),
                    SettingsIcon(icon: BootstrapIcons.gear),
                  ]),
                ),

                Positioned(
                  top: h * 0.54,
                  left: 0,
                  right: 0,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    StartButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ModeSelectScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    RulesButton(),
                    const SizedBox(height: 16),
                    RolesButton(),
                  ]),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}