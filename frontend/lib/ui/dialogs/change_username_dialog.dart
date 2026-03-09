import 'package:areyoughost/ui/dialogs/change_success_dialog.dart';
import 'package:areyoughost/ui/home/home.dart';
import 'package:flutter/material.dart';
import 'package:areyoughost/services/auth_service.dart';
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

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.currentUsername);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _updateUsername() async {
    final newUsername = controller.text.trim();
    if (newUsername == widget.currentUsername) {
      Navigator.pop(context);
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
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปลี่ยนชื่อผู้ใช้งานสำเร็จ')),
      );
    } else {
      setState(() {
        errorMessage = result['error'];
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
                          onPressed: () {
                            ChangeSuccessDialog.show(
                              context: context,
                              title: 'เปลี่ยนชื่อผู้ใช้งานสำเร็จ',
                              message:
                                  '“...กลับเข้าสู่โลกแห่งความหลอน\nบัญชีของคุณเปลี่ยนชื่อสำเร็จ...”',
                              destination: const HomeScreen(),
                            );
                          },
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
