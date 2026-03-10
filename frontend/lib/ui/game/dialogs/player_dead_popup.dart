import 'package:flutter/material.dart';

/// ===============================================================
/// PLAYER DEAD POPUP
/// ---------------------------------------------------------------
/// Popup นี้ใช้เมื่อ backend แจ้งว่า "มีผู้เล่นตาย"
///
/// Backend ต้องส่ง:
/// - roleName
/// - imageUrl
/// - description
///
/// ตัวอย่าง response จาก backend:
///
/// {
///   "roleName": "ผู้เคราะห์ร้าย",
///   "image": "https://api/roles/victim.png",
///   "description": "ผู้เล่นตายจะไม่สามารถพูดได้"
/// }
/// ===============================================================

class PlayerDeadPopup extends StatelessWidget {

  final String roleName;
  final String imageUrl;
  final String description;

  final VoidCallback onClose;

  const PlayerDeadPopup({
    super.key,
    required this.roleName,
    required this.imageUrl,
    required this.description,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {

    return Dialog(
      backgroundColor: Colors.transparent,

      child: Container(
        width: 358,

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

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            /// role name
            Text(
              roleName,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 20),

            /// role image
            Container(
              width: 160,
              height: 160,

              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(16),
              ),

              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),

                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// description
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 24),

            /// confirm button
            ElevatedButton(
              onPressed: onClose,

              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9D9D9),
                foregroundColor: Colors.black,
                elevation: 4,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),

              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 10,
                ),
                child: Text("รับทราบ"),
              ),
            )
          ],
        ),
      ),
    );
  }
}