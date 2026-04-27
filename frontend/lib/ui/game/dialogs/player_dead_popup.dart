import 'package:flutter/material.dart';

class PlayerDeadPopup extends StatelessWidget {
  final String victimLabel;
  final String detailMessage;
  final String imagePath;

  const PlayerDeadPopup({
    super.key,
    required this.victimLabel,
    required this.detailMessage,
    this.imagePath = 'assets/images/player_dead_urn.png',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,

      child: Container(
        width: 360,
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 28,
        ),

        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              blurRadius: 24,
              offset: const Offset(0, 10),
              color: Colors.black.withValues(alpha: 0.25),
            )
          ],
        ),

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            /// หัวข้อ
            const Text(
              "ผู้เคราะห์ร้าย",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: "Charmonman",
                fontSize: 34,
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 24),

            /// กล่องรูป
            Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                    color: Colors.black.withValues(alpha: 0.25),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Image.asset(
                    'assets/images/ash.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),

            /// ชื่อผู้เล่น
            Text(
              victimLabel,
              style: TextStyle(
                fontFamily: "Charmonman",
                fontSize: 22,
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            /// คำอธิบาย
            Text(
              detailMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: "Charmonman",
                fontSize: 16,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 28),

            /// ปุ่ม
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9D9D9),
                foregroundColor: Colors.black,
                elevation: 6,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Text(
                  "รับทราบ",
                  style: TextStyle(
                    fontFamily: "Charmonman",
                    fontSize: 18,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}