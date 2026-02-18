import 'package:areyoughost/ui/widgets/buttons/login_buttons.dart';
import 'package:areyoughost/ui/widgets/icons/friend-icon.dart';
import 'package:areyoughost/ui/widgets/icons/mail-icon.dart';
import 'package:areyoughost/ui/widgets/icons/setting-icon.dart';
import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:areyoughost/ui/widgets/buttons/start_buttons.dart';
import 'package:areyoughost/ui/widgets/buttons/rules_buttons.dart';
import 'package:areyoughost/ui/widgets/buttons/roles_buttons.dart';
import 'package:areyoughost/ui/game/mode_select_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // พื้นหลังรอบ ๆ
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // อัตราส่วนภาพ 390x844
            const double designWidth = 390;
            const double designHeight = 844;

            return SizedBox(
              width: designWidth,
              height: designHeight,
              child: Stack(
                children: [
                  // พื้นหลัง
                  Image.asset(
                    'assets/images/mobileBg.jpg',
                    fit: BoxFit.cover,
                    width: designWidth,
                    height: designHeight,
                  ),

                  // icon มุมขวาบน
                  Positioned(
                    top: 48,
                    right: 10,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MailIcon(), //Mail icon
                        const SizedBox(width: 4),
                        AddFriendIcon(), //Add friends /friends
                        const SizedBox(width: 6),
                        SettingsIcon(icon: BootstrapIcons.gear),
                      ],
                    ),
                  ),
                  Positioned(
                    top: designHeight * 0.54,
                    left: 0,
                    right: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StartButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ModeSelectScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        RulesButton(),
                        const SizedBox(height: 16),
                        RolesButton(),
                      ],
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
