import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/game/player_sign.dart';
import 'package:areyoughost/ui/game/widgets/point_hand.dart';

class PlayerGridDay extends StatelessWidget {
  final List<PlayerModel> players;
  final int myPlayerNumber;
  final int? selectedTarget;
  final bool isVotePhase;
  final Function(int) onPlayerTap;

  const PlayerGridDay({
    super.key,
    required this.players,
    required this.myPlayerNumber,
    required this.selectedTarget,
    required this.isVotePhase,
    required this.onPlayerTap,
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
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: List.generate(crossAxisCount, (colIndex) {
                  final index = rowIndex * crossAxisCount + colIndex;

                  if (index >= players.length) {
                    return const Expanded(child: SizedBox());
                  }

                  final p = players[index];

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          onPlayerTap(p.number);
                        },
                        child: Stack(
                          children: [

                            /// Player Card
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9D9D9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Column(
                                children: [
                                  const SizedBox(height: 6),

                                  /// Player number + name
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

                                  /// Player image
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

                            /// Vote UI
                            if (isVotePhase) ...[

                              /// Wooden Sign
                              if (p.number == myPlayerNumber)
                                if (selectedTarget != null)
                                  PlayerSign(number: selectedTarget!)
                                else
                                  const SizedBox()
                              else
                                PlayerSign(number: (p.number * 3) % 16 + 1),

                              /// ☝️ Point Hand
                              Positioned(
                                right: 32,
                                top: 25,
                                child: Transform.scale(
                                  scale: 1,
                                  child: PointHand(
                                    number: p.number,
                                  ),
                                ),
                              ),
                            ],
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