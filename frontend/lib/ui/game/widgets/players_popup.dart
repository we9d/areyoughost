import 'package:flutter/material.dart';

class PlayersPopup extends StatelessWidget {
  final List<String> players;

  const PlayersPopup({
    super.key,
    required this.players,
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
                const Text(
                  "ผู้เล่น (16)",
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

                separatorBuilder: (_, __) => const SizedBox(height: 6),

                itemBuilder: (context, index) {
                  return Text(
                    "${index + 1}  ${players[index]}",
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.black,
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