import 'package:flutter/material.dart';
import 'package:areyoughost/models/mock_models.dart';

class PlayersPopup extends StatelessWidget {
  final List<PlayerModel> players;
  final int myPlayerNumber;
  final String? myAuthUserId;
  final int activePlayerCount;

  const PlayersPopup({
    super.key,
    required this.players,
    required this.myPlayerNumber,
    this.myAuthUserId,
    required this.activePlayerCount,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),

      child: Container(
        width: 380,
        height: 550,
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),

        decoration: BoxDecoration(
          color: const Color(0xFFEFEFEF),
          borderRadius: BorderRadius.circular(30),
        ),

        child: Column(
          children: [

            /// HEADER
            Row(
              children: [

                const Spacer(),

                /// TITLE
                Text(
                  'ผู้เล่น ($activePlayerCount)',
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.black,
                    decorationThickness: 1,
                  ),
                ),

                const Spacer(),

                /// CLOSE BUTTON
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      size: 24,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            /// PLAYER LIST
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: players.length,

                separatorBuilder: (_, _) => const SizedBox(height: 6),

                itemBuilder: (context, index) {
                  final p = players[index];
                  final self = p.isLocalPlayer(
                    myPlayerNumber: myPlayerNumber,
                    myAuthUserId: myAuthUserId,
                  );
                  return Text(
                    '${p.number}  ${p.name}',
                    style: TextStyle(
                      fontSize: 18,
                      color: self ? const Color(0xFFC2185B) : Colors.black,
                      fontWeight: self ? FontWeight.w700 : FontWeight.w400,
                      height: 1.2,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}