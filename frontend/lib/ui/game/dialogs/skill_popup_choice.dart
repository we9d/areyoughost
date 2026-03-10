import 'package:flutter/material.dart';

/// ===============================================================
/// SKILL POPUP (TYPE 2)
/// ---------------------------------------------------------------
/// Popup นี้ใช้เมื่อผู้เล่นต้องเลือก 1 จาก 2 สกิล
///
/// ขนาด popup: 358 x 383
///
/// Backend ต้องส่ง:
/// - skill1Name
/// - skill2Name
/// - skill1Image
/// - skill2Image
///
/// เมื่อกดเลือก
/// → จะเรียก callback onSkill1 หรือ onSkill2
/// ===============================================================

class SkillPopupChoice extends StatelessWidget {

  final String skill1Name;
  final String skill2Name;

  final String skill1Image;
  final String skill2Image;

  final VoidCallback onSkill1;
  final VoidCallback onSkill2;

  final VoidCallback onClose;

  const SkillPopupChoice({
    super.key,
    required this.skill1Name,
    required this.skill2Name,
    required this.skill1Image,
    required this.skill2Image,
    required this.onSkill1,
    required this.onSkill2,
    required this.onClose,
  });

  Widget skillItem({
    required String name,
    required String imageUrl,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [

          /// Skill Icon Box
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),

              /// Backend image
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(height: 10),

          /// Skill Name
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.black, // ALL TEXT BLACK
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,

      child: Container(
        width: 358,
        height: 383,

        padding: const EdgeInsets.all(24),

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

            /// CLOSE BUTTON
            Positioned(
              top: 0,
              right: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onClose,
                  child: const Icon(
                    Icons.close,
                    color: Colors.black,
                  ),
                ),
              ),
            ),

            /// CONTENT
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                const Text(
                  "เลือกใช้ 1 สกิล?",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [

                    skillItem(
                      name: skill1Name,
                      imageUrl: skill1Image,
                      onTap: onSkill1,
                    ),

                    skillItem(
                      name: skill2Name,
                      imageUrl: skill2Image,
                      onTap: onSkill2,
                    ),

                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}