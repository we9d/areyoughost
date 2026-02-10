import 'package:flutter/material.dart';
import 'package:areyoughost/ui/lobby/lobby_screen.dart';
import 'package:areyoughost/ui/login/login_screen.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ================= Success Popup =================
  void _showRegisterSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        Future.delayed(const Duration(seconds: 1), () {
          if (Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
          }
          // Navigate back to LoginScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        });

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
                  'สมัครบัญชีสำเร็จ',
                  style: TextStyle(
                    fontFamily: 'Charmonman',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '"...ยินดีต้อนรับสู่โลกแห่งความหลอน\n บัญชีของคุณพร้อมใช้งานแล้ว..."',
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

              // ================= Back =================
              Positioned(
                top: 40,
                left: 16,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                ),
              ),

              // ================= Content =================
              Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 80),
                        const Text(
                          'ลงทะเบียน',
                          style: TextStyle(
                            fontFamily: 'Charmonman',
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 30),

                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildTextField(
                                hint: 'ชื่อผู้ใช้งาน',
                                icon: BootstrapIcons.person_circle,
                                controller: _usernameController,
                              ),
                              const SizedBox(height: 10),
                              _buildTextField(
                                hint: 'อีเมล',
                                icon: PhosphorIcons.envelope(),
                                controller: _emailController,
                              ),
                              const SizedBox(height: 10),
                              _buildTextField(
                                hint: 'รหัสผ่าน',
                                icon: PhosphorIcons.lockKey(),
                                controller: _passwordController,
                                obscureText: true,
                              ),
                              const SizedBox(height: 10),
                              _buildTextField(
                                hint: 'ยืนยันรหัสผ่าน',
                                icon: PhosphorIcons.lockKey(),
                                controller: _confirmPasswordController,
                                obscureText: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ================= Register Button =================
                        InnerShadowButton(
                          text: 'สมัครบัญชี',
                          onTap: () {
                            if (_formKey.currentState!.validate()) {
                              // ตรวจสอบว่ารหัสผ่านตรงกันหรือไม่
                              if (_passwordController.text != _confirmPasswordController.text) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'รหัสผ่านไม่ตรงกัน',
                                      style: TextStyle(fontFamily: 'Charmonman'),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                              _showRegisterSuccessDialog(context);
                            }
                          },
                        ),
                        const SizedBox(height: 80),

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

  // ================= TextField =================
  Widget _buildTextField({
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    bool obscureText = false,
  }) {
    return SizedBox(
      width: 258,
      height: 70,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        cursorColor: Colors.black,
        style: const TextStyle(
          fontFamily: 'Charmonman',
          fontSize: 18,
          color: Colors.black,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'กรุณากรอก$hint';
          }
          // ตรวจสอบรูปแบบอีเมลถ้าเป็นช่องอีเมล
          if (hint == 'อีเมล') {
            final emailRegex = RegExp(
              r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
            );
            if (!emailRegex.hasMatch(value.trim())) {
              return 'กรุณากรอกอีเมลให้ถูกต้อง';
            }
          }
          return null;
        },
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontFamily: 'Charmonman',
            fontSize: 18,
            color: Colors.black54,
          ),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, color: Colors.black),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          errorStyle: const TextStyle(
            fontFamily: 'Charmonman',
            fontSize: 12,
            color: Colors.white,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
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
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 2);

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
