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
    return SizedBox(
      width: 87,
      height: 110,
      child: Column(
        children: [
          // Player number
          Align(
            alignment: Alignment.topLeft,
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Avatar
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade300,
            ),
            child: const Icon(
              Icons.person,
              size: 36,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 6),

          // Player name
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
