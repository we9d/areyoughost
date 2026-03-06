import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:areyoughost/ui/login/login_screen.dart';
import 'package:areyoughost/ui/widgets/auth_button.dart';
import 'package:areyoughost/ui/widgets/auth_text_field.dart';
import 'package:areyoughost/ui/widgets/success_dialog.dart';
import 'package:areyoughost/services/auth_service.dart';

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

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.register(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        _showRegisterSuccessDialog(context);
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

  void _showRegisterSuccessDialog(BuildContext context) {
    SuccessDialog.show(
      context: context,
      title: 'สมัครบัญชีสำเร็จ',
      message:
          '"...ยินดีต้อนรับสู่โลกแห่งความหลอน\n บัญชีของคุณพร้อมใช้งานแล้ว..."',
      destination: const LoginScreen(),
    );
  }

  void _goBackToLogin() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /// Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/Login-Register.jpg',
              fit: BoxFit.cover,
            ),
          ),

          /// Content
          Center(
            child: SingleChildScrollView(
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
                        AuthTextField(
                          fieldType: AuthFieldType.username,
                          controller: _usernameController,
                        ),

                        const SizedBox(height: 10),

                        AuthTextField(
                          fieldType: AuthFieldType.email,
                          controller: _emailController,
                        ),

                        const SizedBox(height: 10),

                        AuthTextField(
                          fieldType: AuthFieldType.password,
                          controller: _passwordController,
                        ),

                        const SizedBox(height: 10),

                        AuthTextField(
                          fieldType: AuthFieldType.confirmPassword,
                          controller: _confirmPasswordController,
                          customValidator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณายืนยันรหัสผ่าน';
                            }

                            if (value.contains(' ')) {
                              return 'ไม่สามารถใช้ช่องว่าง กรุณาลองใหม่อีกครั้ง';
                            }

                            if (value != _passwordController.text) {
                              return 'รหัสผ่านไม่ตรงกัน';
                            }

                            return null;
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  AuthButton(
                    text: _isLoading ? 'กำลังสมัครบัญชี...' : 'สมัครบัญชี',
                    onTap: _isLoading ? () {} : _handleRegister,
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
                ],
              ),
            ),
          ),

          /// Back Button
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: Icon(
                PhosphorIcons.caretLeft(),
                color: Colors.white,
                size: 32,
              ),
              onPressed: _goBackToLogin,
            ),
          ),
        ],
      ),
    );
  }
}