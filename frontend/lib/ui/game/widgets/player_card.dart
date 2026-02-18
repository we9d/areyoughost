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
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          const SizedBox(height: 6),

          /// 🔹 Text 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$number $name',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: Colors.black,
              ),
            ),
          ),

          const SizedBox(height: 4),

          /// รูปคนสีดำ default
          Expanded(
            child: Image.asset(
              'assets/images/defaultPlayer.png',
              fit: BoxFit.cover, 
              alignment: Alignment.bottomCenter,
            ),
          ),
        ],
      ),
    );
  }
}
