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
    const int crossAxisCount = 4;
    final int rowCount = (players.length / crossAxisCount).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: List.generate(rowCount, (rowIndex) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: rowIndex < rowCount - 1 ? 8 : 0),
              child: Row(
                children: List.generate(crossAxisCount, (colIndex) {
                  final index = rowIndex * crossAxisCount + colIndex;
                  if (index >= players.length) return const Expanded(child: SizedBox());

                  final p = players[index];

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: colIndex < crossAxisCount - 1 ? 8 : 0,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Column(
                          children: [
                            const SizedBox(height: 6),

                            /// 🔹 เลข + ชื่อ
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '${p.number} ${p.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                  color: Colors.black,
                                ),
                              ),
                            ),

                            const SizedBox(height: 2),

                            /// 🔹รูปคนสีดำ default
                            Expanded(
                              child: Image.asset(
                                'assets/images/defaultPlayer.png',
                                fit: BoxFit.cover,
                                alignment: Alignment.bottomCenter,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          );
        }),
      ),
    );
  }
}
