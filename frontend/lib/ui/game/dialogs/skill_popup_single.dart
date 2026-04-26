import 'package:flutter/material.dart';
import 'skill_popup_result.dart';
import 'package:areyoughost/ui/widgets/network_or_asset_image.dart';

class SkillPopupSingle extends StatelessWidget {
  final String skillName;
  final String description;
  final String image;
  final VoidCallback onUse;

  const SkillPopupSingle({
    super.key,
    required this.skillName,
    required this.description,
    required this.image,
    required this.onUse,
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

            /// ❌ ปุ่มปิด
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// กล่องสกิล (กดได้)
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      onUse();
                    },

                    child: Container(
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

                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),

                        child: Padding(
                          padding: const EdgeInsets.all(0),
                          child: NetworkOrAssetImage(
                            path: image,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  Text(
                    description,
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
