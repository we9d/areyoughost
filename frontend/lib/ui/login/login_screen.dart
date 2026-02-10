import 'package:flutter/material.dart';
import 'package:areyoughost/ui/lobby/lobby_screen.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  // ================= Success Popup =================
  void _showLoginSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFF018A0C),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'เข้าสู่ระบบสำเร็จ',
                  style: TextStyle(
                    fontFamily: 'Charmonman',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.black,
                    decorationThickness: 1,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '“ยินดีต้อนรับกลับมา\nพร้อมลุยความหลอนแล้วหรือยัง?”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Charmonman',
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: 390,
          height: 844,
          child: Stack(
            children: [
              Image.asset(
                'assets/images/Login-Register.jpg',
                width: 390,
                height: 844,
                fit: BoxFit.cover,
              ),
              Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const Text(
                          'เข้าสู่ระบบ',
                          style: TextStyle(
                            fontFamily: 'Charmonman',
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 30),

                        // ================= Username =================
                        _buildTextField(
                          hint: 'ชื่อผู้ใช้งาน',
                          icon: BootstrapIcons.person_circle,
                        ),
                        const SizedBox(height: 10),

                        // ================= Password =================
                        _buildTextField(
                          hint: 'รหัสผ่าน',
                          icon: Icons.lock,
                        ),
                        const SizedBox(height: 24),

                        // ================= Login Button (INNER SHADOW) =================
                        InnerShadowButton(
                          text: 'เข้าสู่ระบบ',
                          onTap: () => _showLoginSuccessDialog(context),
                        ),
                        const SizedBox(height: 80),

                        // ================= Register =================
                        const Text(
                          'ยังไม่มีบัญชีใช่ไหม?',
                          style: TextStyle(
                            fontFamily: 'Charmonman',
                            fontSize: 20,
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const SizedBox(height: 10),

                        InnerShadowButton(
                          text: 'สมัครบัญชี',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= Reusable Widgets =================

  Widget _buildTextField({
    required String hint,
    required IconData icon,
  }) {
    return SizedBox(
      width: 258,
      height: 58,
      child: TextField(
        cursorColor: Colors.black,
        style: const TextStyle(
          fontFamily: 'Charmonman',
          fontSize: 18,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: 'Charmonman',
            fontSize: 18,
            color: Colors.black,
          ),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: Colors.black),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
        ),
      ),
    );
  }
}

/// ================= INNER SHADOW BUTTON =================
class InnerShadowButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const InnerShadowButton({
    super.key,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 172,
      height: 40,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1C232),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              painter: _InnerShadowPainter(),
              child: Container(),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Center(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontFamily: 'Charmonman',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InnerShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final paint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter =
          const MaskFilter.blur(BlurStyle.inner, 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(1),
        const Radius.circular(14),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
