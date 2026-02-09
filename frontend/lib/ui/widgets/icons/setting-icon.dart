import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';


class SettingsIcon extends StatelessWidget {
  // const SettingsIcon({super.key});
   final IconData icon;
  const SettingsIcon({super.key,required this.icon});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon:  Icon(
        icon,
        color: Colors.white,
        size: 25,
      ),
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _SettingsDialog(),
        );
      },
    );
  }
}
class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: 358,
        height: 328,
        child: Stack(
          children: [
            //  ปุ่มปิด
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: Colors.black,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            //  Title
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: const Text(
                  'การตั้งค่า',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                    decorationColor: Colors.black, // สีเส้นใต้
                    color: Colors.black,
                  ),
                ),
              ),
            ),

            //  Content (เผื่อขยาย)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 70, 10, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: const [
                  Text('ชื่อผู้ใช้งาน', style: TextStyle(color: Colors.black,)),
                  SizedBox(height: 8),
                  Text('เสียงประกอบ',style: TextStyle(color: Colors.black,)),
                  SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
