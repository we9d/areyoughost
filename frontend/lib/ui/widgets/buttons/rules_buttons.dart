import 'package:areyoughost/ui/widgets/buttons/decoration/shadow.dart';
import 'package:flutter/material.dart';

class RulesButton extends StatelessWidget {
  const RulesButton({super.key});
  
  void _showRules(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _RulesDialog(), // เปลี่ยนมาใช้ dialog แบบใหม่
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
        onPressed: () => _showRules(context),
        child: const Text(
          "กติกา",
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

class _RulesDialog extends StatelessWidget {
  const _RulesDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500,
        height: 550,
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Color.fromARGB(255, 0, 0, 0),
                  size: 24,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            //Title
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'กติกา',
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
                "รายละเอียดกติกา",
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
