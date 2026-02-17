import 'package:flutter/material.dart' as m;
import 'shadow_button.dart';
import 'random_role_screen.dart';

class ModeSelectScreen extends m.StatelessWidget {
  const ModeSelectScreen({super.key});

  @override
  m.Widget build(m.BuildContext context) {
    return m.Scaffold(
      body: m.Stack(
        children: [
          // ===== BG =====
          m.Positioned.fill(
            child: m.Image.asset(
              'assets/images/ModeSelectBg.jpg',
              fit: m.BoxFit.cover,
            ),
          ),

          // ===== DARK OVERLAY =====
          m.Positioned.fill(
            child: m.Container(
              color: m.Colors.black.withOpacity(0.55),
            ),
          ),

          m.SafeArea(
            child: m.Column(
              children: [
                // ===== BACK =====
                m.Align(
                  alignment: m.Alignment.centerLeft,
                  child: m.IconButton(
                    icon: const m.Icon(
                      m.Icons.arrow_back_ios_new,
                      color: m.Colors.white,
                    ),
                    onPressed: () => m.Navigator.pop(context),
                  ),
                ),

                const m.Spacer(),

                // ===== TITLE =====
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

                // ===== PLAY NOW =====
                ShadowButton(
                  width: 240,
                  height: 62,
                  color: const m.Color(0xFF3A5A7A), // ✅ น้ำเงิน
                  gradient: m.LinearGradient(
                    begin: m.Alignment.topCenter,
                    end: m.Alignment.bottomCenter,
                    colors: [
                      m.Colors.white.withOpacity(0.25),
                      m.Colors.transparent,
                      m.Colors.black.withOpacity(0.65),
                    ],
                  ),
                  onPressed: () {
                    m.Navigator.push(
                      context,
                      m.MaterialPageRoute(
                        builder: (_) =>
                            const RandomRoleScreen(roomId: 'mode_select'),
                      ),
                    );
                  },
                  child: const m.Text(
                    'เล่นทันที',
                    style: m.TextStyle(
                      fontSize: 22,
                      fontWeight: m.FontWeight.w800,
                      color: m.Colors.white,
                      letterSpacing: 0.3,
                      shadows: [
                        m.Shadow(
                          blurRadius: 4,
                          color: m.Colors.black87,
                          offset: m.Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),

                const m.SizedBox(height: 18),

                // ===== PLAY WITH FRIENDS (DISABLED) =====
                ShadowButton(
                  width: 240,
                  height: 62,
                  color: const m.Color(0xFF6A1F2B), // ✅ แดง
                  gradient: m.LinearGradient(
                    begin: m.Alignment.topCenter,
                    end: m.Alignment.bottomCenter,
                    colors: [
                      m.Colors.white.withOpacity(0.12),
                      m.Colors.transparent,
                      m.Colors.black.withOpacity(0.55),
                    ],
                  ),
                  onPressed: null,
                  child: const m.Text(
                    'เล่นกับเพื่อน',
                    style: m.TextStyle(
                      fontSize: 22,
                      fontWeight: m.FontWeight.w800,
                      color: m.Colors.white54,
                    ),
                  ),
                ),

                const m.Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
