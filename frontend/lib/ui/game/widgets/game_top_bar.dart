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
        padding: const EdgeInsets.fromLTRB(14, 24, 14, 6),
        child: SizedBox(
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              /// 🚪 EXIT
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onExitTap,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      PhosphorIcons.signOut(),
                      size: 25,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              /// ⏱ TITLE
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 17),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      shadows: [
                        Shadow(
                          blurRadius: 6,
                          color: Colors.black87,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              /// 👥 PLAYERS
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onPlayerTap,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      PhosphorIcons.usersThree(),
                      size: 25,
                      color: Colors.white,
                    ),
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