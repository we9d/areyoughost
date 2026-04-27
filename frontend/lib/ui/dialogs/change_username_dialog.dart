import 'package:flutter/material.dart';
import 'package:areyoughost/services/auth_service.dart';
import 'package:areyoughost/ui/dialogs/change_success_dialog.dart';
import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';

class ChangeUsernameDialog extends StatefulWidget {
  final String currentUsername;

  const ChangeUsernameDialog({super.key, required this.currentUsername});

  @override
  State<ChangeUsernameDialog> createState() => _ChangeUsernameDialogState();
}

class _ChangeUsernameDialogState extends State<ChangeUsernameDialog> {
  late TextEditingController controller;
  bool isLoading = false;
  String? errorMessage;
  static const String _invalidUsernameMessage =
      'ไม่สามารถใช้สัญลักษณ์พิเศษได้ กรุณาลองใหม่อีกครั้ง';

  String _displayError(dynamic error) {
    final text = (error ?? '').toString().trim();
    if (text.isEmpty) {
      return 'ไม่สามารถเปลี่ยนชื่อได้ในขณะนี้ กรุณาลองใหม่อีกครั้ง';
    }
    if (text.toLowerCase().contains('username already taken')) {
      return 'ชื่อผู้ใช้นี้ถูกใช้งานแล้ว กรุณาเปลี่ยนชื่อใหม่';
    }
    if (text.contains('FormatException') || text.contains('Unexpected end of input')) {
      return 'เซิร์ฟเวอร์ตอบกลับไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง';
    }
    return text;
  }

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.currentUsername);
    controller.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onUsernameChanged);
    controller.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final validationError = _validateUsernameInput(controller.text.trim());
    if (!mounted) return;
    setState(() {
      errorMessage = validationError;
    });
  }

  String? _validateUsernameInput(String username) {
    if (username.isEmpty) return null;

    // Allow only English letters, digits, and underscore.
    if (username.contains(' ') || !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      return _invalidUsernameMessage;
    }

    final serviceError = AuthService.validateUsername(username);
    if (serviceError != null) {
      return serviceError;
    }
    return null;
  }

  Future<void> _updateUsername() async {
    final newUsername = controller.text.trim();
    if (newUsername == widget.currentUsername) {
      Navigator.pop(context);
      return;
    }

    final validationError = _validateUsernameInput(newUsername);
    if (validationError != null) {
      setState(() {
        errorMessage = validationError;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final result = await AuthService.updateUsername(newUsername);

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    if (result['success']) {
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      rootNavigator.pop();
      ChangeSuccessDialog.show(
        context: rootNavigator.context,
        title: 'เปลี่ยนชื่อผู้ใช้งานสำเร็จ',
        message: '...กลับเข้าสู่โลกแห่งความหลอน\nบัญชีของคุณเปลี่ยนชื่อสำเร็จ...',
        duration: const Duration(milliseconds: 1400),
      );
    } else {
      setState(() {
        errorMessage = _displayError(result['error']);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 358,
        height: 330,
        child: Stack(
          children: [
            /// ปุ่มย้อนกลับ
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.chevron_left,
                  color: Colors.black,
                  size: 33,
                ),
                onPressed: isLoading ? null : () => Navigator.pop(context),
              ),
            ),

            /// ปุ่มปิด
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: isLoading ? null : () => Navigator.pop(context),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              child: Column(
                children: [
                  const Text(
                    'เปลี่ยนชื่อผู้ใช้งาน',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.black,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// ช่องกรอกชื่อ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      enabled: !isLoading,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(color: Colors.black, fontSize: 14),
                    ),
                  ),

                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),

                  const Spacer(),

                  if (isLoading)
                    const CircularProgressIndicator()
                  else
                    /// ปุ่มล่าง
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Shadow(
                          height: 38,
                          width: 85,
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.fromARGB(255, 175, 174, 174),
                              Color.fromARGB(255, 208, 208, 208),
                            ],
                            stops: [0.0, 1.5],
                          ),
                          onPressed: () => Navigator.pop(context), //  ปิด popup
                          child: const Text(
                            "ยกเลิก",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        Shadow(
                          height: 38,
                          width: 85,
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.fromARGB(255, 180, 147, 54),
                              Color(0xFFE7C66A),
                            ],
                            stops: [0.0, 1.5],
                          ),
                          onPressed: _updateUsername,
                          child: const Text(
                            "ยืนยัน",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
