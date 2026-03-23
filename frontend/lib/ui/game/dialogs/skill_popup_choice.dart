import 'package:flutter/material.dart';
import 'skill_popup_result.dart';

class SkillPopupChoice extends StatelessWidget {
  final String skill1Name;
  final String skill1Description;
  final String skill1Image;
  final String skill2Name;
  final String skill2Description;
  final String skill2Image;
  final VoidCallback onSkill1;
  final VoidCallback onSkill2;
  final VoidCallback onClose;

  const SkillPopupChoice({
    super.key,
    required this.skill1Name,
    required this.skill1Description,
    required this.skill1Image,
    required this.skill2Name,
    required this.skill2Description,
    required this.skill2Image,
    required this.onSkill1,
    required this.onSkill2,
    required this.onClose,
  });

  Widget skillItem({
    required BuildContext context,
    required String name,
    required String description,
    required String image,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [

          /// ICON BOX
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                  color: Colors.black.withOpacity(0.25),
                )
              ],
            ),

            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                image,
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(height: 18),

          /// NAME
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: "Charmonman",
                fontSize: 20,
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const SizedBox(height: 6),

          /// DESCRIPTION
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: "Charmonman",
                fontSize: 14,
                color: Colors.black,
              ),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),

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
              child: GestureDetector(
                onTap: onClose,
                child: const Icon(
                  Icons.close,
                  color: Colors.black,
                ),
              ),
            ),

            /// CONTENT
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    const Text(
                      "เลือกใช้ 1 สกิล?",
                      style: TextStyle(
                        fontFamily: "Charmonman",
                        fontSize: 32,
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      "ตลอดทั้งเกมใช้ได้ทั้งหมด 1 ครั้ง",
                      style: TextStyle(
                        fontFamily: "Charmonman",
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 26),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        /// SKILL 1
                        Expanded(
                          child: Center(
                            child: skillItem(
                              context: context,
                              name: skill1Name,
                              description: skill1Description,
                              image: skill1Image,
                              onTap: onSkill1,
                            ),
                          ),
                        ),

                        /// SKILL 2
                        Expanded(
                          child: Center(
                            child: skillItem(
                              context: context,
                              name: skill2Name,
                              description: skill2Description,
                              image: skill2Image,
                              onTap: onSkill2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
