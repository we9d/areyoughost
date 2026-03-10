import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:flutter/material.dart';

class RolesButton extends StatelessWidget {
  const RolesButton({super.key});

  void _showRoles(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const RolesDialog(), // เปลี่ยนมาใช้ dialog แบบใหม่
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Shadow(
        height: 60,
        width: 150,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.fromARGB(255, 34, 53, 72), Color(0xFF3A5A7A)],
          stops: [0.0, 1.25],
        ),
        onPressed: () => _showRoles(context),

        child: const Text(
          "บทบาท",
          style: TextStyle(
            color: Color.fromARGB(255, 255, 255, 255),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class RolesDialog extends StatelessWidget {
  const RolesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 500,
        height: 550,
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black, size: 24),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Title
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'บทบาท',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        decorationThickness: 1.5,
                        decorationColor: Colors.black,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Content
            const Center(
              child: Text(
                "รายละเอียดบทบาท",
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
