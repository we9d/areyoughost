import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/game/player_sign.dart';
import 'package:areyoughost/ui/game/widgets/point_hand.dart';
import 'package:areyoughost/ui/widgets/network_or_asset_image.dart';

class PlayerGridDay extends StatelessWidget {
  final List<PlayerModel> players;
  final int myPlayerNumber;
  /// Logged-in account id; matches [PlayerModel.playerId] from `room.state`.
  final String? myAuthUserId;
  final Map<int, int> dayVoteTargetByVoter;
  final Map<int, int> dayVoteCountByTarget;
  final bool dayVoteEnabled;
  final Function(int) onPlayerTap;
  final Map<int, String> skillIconByPlayerNumber;
  final Map<int, bool> aliveByPlayerNumber;

  const PlayerGridDay({
    super.key,
    required this.players,
    required this.myPlayerNumber,
    this.myAuthUserId,
    required this.dayVoteTargetByVoter,
    required this.dayVoteCountByTarget,
    required this.dayVoteEnabled,
    required this.onPlayerTap,
    this.skillIconByPlayerNumber = const <int, String>{},
    this.aliveByPlayerNumber = const <int, bool>{},
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
                  final isAlive = aliveByPlayerNumber[p.number] ?? true;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          onPlayerTap(p.number);
                        },
                        child: Stack(
                          // Without expand, Stack width follows the narrowest non-positioned
                          // child (e.g. short "1 p01" text), so card 1 looked half-width.
                          fit: StackFit.expand,
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
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        height: 1.1,
                                        color: p.isLocalPlayer(
                                                myPlayerNumber: myPlayerNumber,
                                                myAuthUserId: myAuthUserId)
                                            ? const Color(0xFFC2185B)
                                            : Colors.black,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 2),

                                  /// Player image
                                  Expanded(
                                    child: isAlive
                                        ? Image.asset(
                                            'assets/images/defaultPlayer.png',
                                            fit: BoxFit.cover,
                                            alignment: Alignment.bottomCenter,
                                          )
                                        : Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Image.asset(
                                              'assets/images/player_dead_urn.png',
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, _, _) => Image.asset(
                                                'assets/images/ash.png',
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),

                            if (skillIconByPlayerNumber.containsKey(p.number))
                              Positioned(
                                bottom: 6,
                                right: 6,
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: NetworkOrAssetImage(
                                      path: skillIconByPlayerNumber[p.number]!,
                                      fit: BoxFit.contain,
                                      fallback: const Icon(
                                        Icons.auto_fix_high,
                                        size: 14,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            /// Day vote UI: sign = who this player voted,
                            /// point hand number = vote count received.
                            if (dayVoteEnabled) ...[
                              if (dayVoteTargetByVoter[p.number] != null)
                                PlayerSign(number: dayVoteTargetByVoter[p.number]!),
                              if ((dayVoteCountByTarget[p.number] ?? 0) > 0)
                                Positioned(
                                  right: 32,
                                  top: 25,
                                  child: Transform.scale(
                                    scale: 1,
                                    child: PointHand(
                                      number: dayVoteCountByTarget[p.number]!,
                                      numberColor:
                                          dayVoteTargetByVoter[myPlayerNumber] == p.number
                                          ? Colors.red
                                          : Colors.black,
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