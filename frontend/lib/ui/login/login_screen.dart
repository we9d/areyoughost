import 'package:flutter/material.dart';
import 'package:areyoughost/ui/home/home.dart';
import 'package:areyoughost/ui/register/register_screen.dart';
import 'package:areyoughost/ui/widgets/auth_button.dart';
import 'package:areyoughost/ui/widgets/auth_text_field.dart';
import 'package:areyoughost/ui/widgets/success_dialog.dart';
import 'package:areyoughost/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        _showLoginSuccessDialog(context);
      } else {
        setState(() {
          _errorMessage = result['error'] ?? 'เกิดข้อผิดพลาด';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดในการเชื่อมต่อ';
        _isLoading = false;
      });
    }
  }

  void _showLoginSuccessDialog(BuildContext context) {
    SuccessDialog.show(
      context: context,
      title: 'เข้าสู่ระบบสำเร็จ',
      message: '"ยินดีต้อนรับกลับมา\nพร้อมลุยความหลอนแล้วหรือยัง?"',
      destination: const HomeScreen(),
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
                fit: BoxFit.cover,
              ),

              Positioned(
                top: 40,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HomeScreen(),
                      ),
                    );
                  },
                ),
              ),

              Center(
                child: SingleChildScrollView(
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

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            AuthTextField(
                              fieldType: AuthFieldType.username,
                              controller: _usernameController,
                            ),
                            const SizedBox(height: 10),
                            AuthTextField(
                              fieldType: AuthFieldType.password,
                              controller: _passwordController,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      AuthButton(
                        text: _isLoading ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ',
                        onTap: _isLoading ? () {} : _handleLogin,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontFamily: 'Charmonman',
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 80),

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

                      AuthButton(
                        text: 'สมัครบัญชี',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
