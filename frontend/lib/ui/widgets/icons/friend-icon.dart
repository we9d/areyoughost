import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

class AddFriendIcon extends StatelessWidget {
  const AddFriendIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: const Icon(
        BootstrapIcons.person_plus_fill,
        color: Colors.white,
        size: 25,
      ),
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _AddFriendDialog(),
        );
      },
    );
  }
}
class _AddFriendDialog extends StatelessWidget {
  const _AddFriendDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: 500,
        height: 550,
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

            //Title
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'เพื่อน',
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

            //  Content (เผื่อขยาย)
            Padding(
              padding: const EdgeInsets.only(top: 70),
              child: Center(
                child: Text(
                  'พื้นที่สำหรับรายชื่อเพื่อน / เพิ่มเพื่อน',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

