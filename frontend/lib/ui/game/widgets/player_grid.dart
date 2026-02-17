import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';

class PlayerGrid extends StatelessWidget {
  final List<PlayerModel> players;

  const PlayerGrid({
    super.key,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: players.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.68, // ใกล้ Figma
        ),
        itemBuilder: (context, index) {
          final p = players[index];

          return Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// 🔹 เลข + ชื่อผู้เล่น
                Row(
                  children: [
                    Text(
                      p.number.toString(),
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
                        p.name,
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

                const Spacer(flex: 2),

                /// 🔹 รูป defaultPlayer (เล็ก / กลาง / พอดี Figma)
                const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Image(
                      image: AssetImage(
                        'assets/images/defaultPlayer.png',
                      ),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                const Spacer(flex: 2),
              ],
            ),
          );
        },
      ),
    );
  }
}
