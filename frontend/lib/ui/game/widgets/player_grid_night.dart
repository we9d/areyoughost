import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';
import 'package:areyoughost/ui/game/player_sign.dart';
import 'package:areyoughost/ui/game/ghost_hand.dart';
import 'package:areyoughost/ui/widgets/network_or_asset_image.dart';

/// กลางคืน: ฝ่ายผีโหวตฆ่า — แสดงมือกระดูก + ป้ายเลขเป้าหมายที่การ์ดเป้าหมาย (และมือที่การ์ดตัวเองก่อนเลือก)
class PlayerGridNight extends StatelessWidget {
  final List<PlayerModel> players;
  final int myPlayerNumber;
  final String? myAuthUserId;
  /// ใครโหวตใคร: key=voterNumber, value=targetNumber
  final Map<int, int> ghostVoteTargetByVoter;
  /// จำนวนโหวตที่แต่ละเป้าหมายได้รับ: key=targetNumber, value=count
  final Map<int, int> ghostVoteCountByTarget;
  /// เปิด UI โหวตกลางคืนของฝ่ายผี (มือกระดูก + ป้าย)
  final bool ghostNightKillVoteEnabled;
  final Function(int) onPlayerTap;
  final Map<int, String> skillIconByPlayerNumber;
  final Map<int, bool> aliveByPlayerNumber;

  const PlayerGridNight({
    super.key,
    required this.players,
    required this.myPlayerNumber,
    this.myAuthUserId,
    required this.ghostVoteTargetByVoter,
    required this.ghostVoteCountByTarget,
    required this.ghostNightKillVoteEnabled,
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
                          fit: StackFit.expand,
                          children: [
                            /// กล่องผู้เล่น
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9D9D9),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: Column(
                                children: [
                                  const SizedBox(height: 6),

                                  /// เลข + ชื่อ
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

                                  /// รูปผู้เล่น
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
                            /// โหวตฆ่ากลางคืน (ฝ่ายผี)
                            if (ghostNightKillVoteEnabled) ...[
                              // ป้าย: เลขที่ผู้เล่น "คนนั้น" โหวต
                              if (ghostVoteTargetByVoter[p.number] != null)
                                PlayerSign(number: ghostVoteTargetByVoter[p.number]!),
                              // มือกระดูก: จำนวนโหวตที่ผู้เล่น "คนนี้" ได้รับจากคนอื่น
                              if ((ghostVoteCountByTarget[p.number] ?? 0) > 0)
                                Positioned(
                                  right: 32,
                                  top: 25,
                                  child: GhostHand(
                                    number: ghostVoteCountByTarget[p.number]!,
                                    numberColor:
                                        ghostVoteTargetByVoter[myPlayerNumber] == p.number
                                        ? Colors.red
                                        : Colors.black,
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
