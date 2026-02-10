import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

class MailIcon extends StatelessWidget {
  const MailIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(
        BootstrapIcons.envelope_fill,
        color: Colors.white,
        size: 25,
      ),
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return const _MailDialog();
          },
        );
      },
    );
  }
}

class _MailDialog extends StatelessWidget {
  const _MailDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 358,
        height: 187,
        child: Stack(
          children: [
            // ปุ่มปิด
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // เนื้อหา
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 60, height: 0.8, color: Colors.black),
                  const SizedBox(width: 12),
                  const Text('ไม่มีคำเชิญชวน', style: TextStyle(fontSize: 20,color:Colors.black), ),
                  const SizedBox(width: 12),
                  Container(width: 60, height: 0.8, color: Colors.black),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
