import 'package:flutter/material.dart';
import 'skill_popup_result.dart';

class SkillPopupSingle extends StatelessWidget {

  const SkillPopupSingle({super.key});

  void _useSkill(BuildContext context) {

    /// ปิด popup เดิม
    Navigator.pop(context);

    /// เปิด popup ผลลัพธ์
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SkillPopupResult(),
    );
  }

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
          boxShadow: [
            BoxShadow(
              blurRadius: 24,
              offset: const Offset(0, 10),
              color: Colors.black.withOpacity(0.25),
            )
          ],
        ),

        child: Stack(
          children: [

            /// ❌ ปุ่มปิด
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

                  const Text(
                    "สกิลตาวิเศษ",
                    style: TextStyle(
                      fontFamily: "Charmonman",
                      fontSize: 32,
                    ),
                  ),

                  const SizedBox(height: 22),

                  /// กล่องสกิล (กดได้)
                  GestureDetector(
                    onTap: () => _useSkill(context),

                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D9D9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 8,
                            color: Colors.black26,
                          )
                        ],
                      ),

                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),

                        child: Image.asset(
                          "assets/images/skill_eye.png",
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    "เลือกผู้เล่น 1 คน\nเพื่อทำการตรวจฝ่าย",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: "Charmonman",
                      fontSize: 18,
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