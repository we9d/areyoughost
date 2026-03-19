import 'package:flutter/material.dart';

class SkillPopupResult extends StatelessWidget {
  const SkillPopupResult({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,

      child: Container(
        width: 358,
        height: 383,

        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 24,
        ),

        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(28),
        ),

        child: Stack(
          children: [

            /// ❌ ปิด popup
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 28),
              ),
            ),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.circular(20),
                    ),

                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),

                      child: Image.asset(
                        "assets/images/skill_eye.png",
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    "สกิลตาวิเศษ",
                    style: TextStyle(
                      fontFamily: "Charmonman",
                      fontSize: 32,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    "1 น้องข้าว หมายเลขฝ่าย\n“ผี”",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: "Charmonman",
                      fontSize: 20,
                    ),
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