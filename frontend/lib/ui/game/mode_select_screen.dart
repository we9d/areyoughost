import 'package:flutter/material.dart' as m;
import 'random_role_screen.dart';

import 'package:areyoughost/ui/widgets/buttons/playnow_button.dart';
import 'package:areyoughost/ui/widgets/buttons/playtogether_button.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ModeSelectScreen extends m.StatelessWidget {
  const ModeSelectScreen({super.key});

  @override
  m.Widget build(m.BuildContext context) {
    return m.Scaffold(
      body: m.Stack(
        children: [
          // BG
          m.Positioned.fill(
            child: m.Image.asset(
              'assets/images/ModeSelectBg.jpg',
              fit: m.BoxFit.cover,
            ),
          ),

          // DARK OVERLAY
          m.Positioned.fill(
            child: m.Container(
              color: m.Colors.black.withOpacity(0.55),
            ),
          ),

          // ===== CONTENT =====
          m.SafeArea(
            child: m.Column(
              children: [
                // BACK (lowered)
                m.Padding(
                  padding: const m.EdgeInsets.only(top: 24, left: 6),
                  child: m.Align(
                    alignment: m.Alignment.centerLeft,
                    child: m.IconButton(
                      icon: m.Icon(
                        PhosphorIcons.caretLeft(),
                        size: 32,
                        color: m.Colors.white,
                      ),
                      splashRadius: 20,
                      onPressed: () => m.Navigator.pop(context),
                    ),
                  ),
                ),

                const m.Spacer(),

                // TITLE
                const m.Text(
                  'เลือกโหมด',
                  style: m.TextStyle(
                    fontSize: 32,
                    fontWeight: m.FontWeight.w700,
                    color: m.Colors.white,
                    shadows: [
                      m.Shadow(
                        blurRadius: 6,
                        color: m.Colors.black87,
                        offset: m.Offset(0, 2),
                      ),
                    ],
                  ),
                ),

                const m.SizedBox(height: 36),

                PlaynowButton(
                  onPressed: () {
                    m.Navigator.push(
                      context,
                      m.MaterialPageRoute(
                        builder: (_) =>
                            const RandomRoleScreen(roomId: 'mode_select'),
                      ),
                    );
                  },
                ),

                const m.SizedBox(height: 18),

                PlaytogetherButton(onPressed: () {}),

                const m.Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
