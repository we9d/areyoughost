import 'package:flutter/material.dart';
// removed unused game_screen import; use relative import for random_role_screen
import 'random_role_screen.dart';

class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // =========================
          // Background Image
          // =========================
          Positioned.fill(
            child: Image.asset(
              'assets/images/ModeSelectBg.jpg',
              fit: BoxFit.cover,
            ),
          ),

          // =========================
          // Dark Overlay
          // =========================
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.55),
            ),
          ),

          // =========================
          // Main Content
          // =========================
          SafeArea(
            child: Column(
              children: [
                // =========================
                // Top Bar (Back Button)
                // =========================
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ),

                const Spacer(),

                // =========================
                // Title
                // =========================
                const Text(
                  'เลือกโหมด',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 6,
                        color: Colors.black87,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // =========================
                // Play Now Button
                // =========================
                _PrimaryButton(
                  text: 'เล่นทันที',
                  color: const Color(0xFF4E6E8E),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RandomRoleScreen(roomId: 'mode_select'),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // =========================
                // Play With Friends (Disabled)
                // =========================
                _PrimaryButton(
                  text: 'เล่นกับเพื่อน',
                  color: const Color(0xFF7B2D2D),
                  onPressed: null,
                ),
                // NOTE:
                // ปุ่มนี้ intentionally disabled
                // สำหรับ future feature: invite / create room

                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// Primary Button Widget
// =========================
class _PrimaryButton extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    required this.text,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null;

    return SizedBox(
      width: 220,
      height: 60,
      child: Container(
        decoration: BoxDecoration(
          color: isDisabled ? color.withOpacity(0.5) : color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: isDisabled ? null : [
            // Inner shadow effect
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              spreadRadius: -1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDisabled ? Colors.white54 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
