import 'package:flutter/material.dart';

class PlayerSign extends StatelessWidget {
  final int number;

  const PlayerSign({
    super.key,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: Transform.translate(
          offset: const Offset(1.5, 38),
          child: Stack(
            alignment: Alignment.center,
            children: [
              /// ป้ายไม้
              Image.asset(
                "assets/images/Sign.png",
                width: 180,
              ),

              /// ตัวเลขบนป้าย
              Transform.translate(
                offset: const Offset(-1.5, -1),
                child: Text(
                  "$number",
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}