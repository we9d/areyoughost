import 'package:flutter/material.dart';

class SkillPopupResult extends StatelessWidget {
  final String skillName;
  final String skillImage;
  final String resultMessage;

  const SkillPopupResult({
    super.key,
    required this.skillName,
    required this.skillImage,
    this.resultMessage = "1 น้องข้าว หมายเลขฝ่าย\n“ผี”",
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),

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

            /// ❌ ปิด popup
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 28, color: Colors.black),
              ),
            ),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  Text(
                    skillName,
                    style: const TextStyle(
                      fontFamily: "Charmonman",
                      fontSize: 32,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9D9D9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                          color: Colors.black.withOpacity(0.25),
                        )
                      ],
                    ),

                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),

                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Image.asset(
                          skillImage,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  Text(
                    resultMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: "Charmonman",
                      fontSize: 20,
                      color: Colors.black,
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
