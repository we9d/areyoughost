import 'package:flutter/material.dart';

/// ===============================================================
/// SKILL POPUP (TYPE 1)
/// ---------------------------------------------------------------
/// Popup นี้ใช้เมื่อผู้เล่นกด "ปุ่มสกิล" จาก ChatInputRow
///
/// ขนาด popup: 358 x 383
///
/// เมื่อผู้เล่นกด "รูปสกิล"
/// → จะเรียก callback onUseSkill()
///
/// Backend team ต้องเชื่อม:
/// - skillName
/// - description
/// - imageUrl
///
/// imageUrl จะมาจาก backend API
/// ===============================================================

class SkillPopupSingle extends StatelessWidget {
  final String skillName;
  final String description;
  final String imageUrl;

  /// callback เมื่อผู้เล่นกดใช้สกิล
  final VoidCallback onUseSkill;

  /// callback ปิด popup
  final VoidCallback onClose;

  const SkillPopupSingle({
    super.key,
    required this.skillName,
    required this.description,
    required this.imageUrl,
    required this.onUseSkill,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,

      child: Container(
        width: 358,
        height: 383,

        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 20,
        ),

        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(28),

          /// shadow ใกล้เคียง Figma
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

            /// ปุ่มปิด
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close),
              ),
            ),

            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                /// ชื่อสกิล
                Text(
                  skillName,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 20),

                /// รูปสกิล
                GestureDetector(
                  onTap: onUseSkill,
                  child: Container(
                    width: 160,
                    height: 160,

                    decoration: BoxDecoration(
                      color: const Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),

                      /// =====================================================
                      /// BACKEND NOTE
                      /// -----------------------------------------------------
                      /// imageUrl จะถูกส่งมาจาก backend
                      ///
                      /// ตัวอย่าง
                      /// https://api.yourgame.com/skills/investigate.png
                      /// =====================================================
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                /// คำอธิบายสกิล
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}