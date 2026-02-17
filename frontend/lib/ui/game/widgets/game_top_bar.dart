import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class GameTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onExitTap;
  final VoidCallback onPlayerTap;

  const GameTopBar({
    super.key,
    required this.title,
    required this.onExitTap,
    required this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: SizedBox(
          height: 36, // ⬅️ ต่ำกว่าเดิม ดูโปรกว่า
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              /// 🚪 ออกจากเกม
              GestureDetector(
                onTap: onExitTap,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 32,
                  child: Icon(
                    PhosphorIcons.signOut(),
                    size: 32.0,
                    color: Colors.white,
                  ),
                ),
              ),

              /// ⏱ เวลากลางคืน
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14, // ⬅️ Figma ใกล้ 14 มากกว่า
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

              /// 👥 รายชื่อผู้เล่น
              GestureDetector(
                onTap: onPlayerTap,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 32,
                  child: Icon(
                    PhosphorIcons.usersThree(),
                    size: 32.0,
                    color: Colors.white,
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
