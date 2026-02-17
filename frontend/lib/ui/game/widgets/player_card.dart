import 'package:flutter/material.dart';

class PlayerCard extends StatelessWidget {
  final int number;
  final String name;

  const PlayerCard({
    super.key,
    required this.number,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// 🔹 เลข + ชื่อ (ดำ / ตัวหนา / ไม่มีเงา)
          Row(
            children: [
              Text(
                number.toString(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),

          const Spacer(),

          /// 🔹 Avatar (defaultPlayer.png)
          Center(
            child: Image.asset(
              'assets/images/defaultPlayer.png',
              width: 46,
              height: 46,
              fit: BoxFit.contain,
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}
