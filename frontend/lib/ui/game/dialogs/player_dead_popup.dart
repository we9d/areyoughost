import 'package:flutter/material.dart';

class PlayerDeadPopup extends StatelessWidget {
  const PlayerDeadPopup({super.key});

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
              color: Colors.black.withOpacity(0.25),
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
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  "assets/images/death_ash.jpg",
                  fit: BoxFit.contain,
                ),
              ),
            ),

            const SizedBox(height: 22),

            /// ชื่อผู้เล่น
            const Text(
              "2 น้องปอนด์",
              style: TextStyle(
                fontFamily: "Charmonman",
                fontSize: 22,
              ),
            ),

            const SizedBox(height: 10),

            /// คำอธิบาย
            const Text(
              "ผู้เล่นที่ตายจะไม่สามารถพูดได้จนกว่าเกมจะจบ",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: "Charmonman",
                fontSize: 16,
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
              child: const Text(
                "รับทราบ",
                style: TextStyle(
                  fontFamily: "Charmonman",
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}