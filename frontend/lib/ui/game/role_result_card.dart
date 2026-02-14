import 'dart:async';
import 'package:flutter/material.dart';

class RoleResultCard extends StatefulWidget {
  final String roleName;
  final String description;
  final String imagePath;
  final Duration showDuration;
  final VoidCallback? onComplete;

  const RoleResultCard({
    super.key,
    required this.roleName,
    required this.description,
    required this.imagePath,
    this.showDuration = const Duration(seconds: 5),
    this.onComplete,
  });

  @override
  State<RoleResultCard> createState() => _RoleResultCardState();
}

class _RoleResultCardState extends State<RoleResultCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<int> _dotAnimation;
  Timer? _completeTimer;

  @override
  void initState() {
    super.initState();

    // dots animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _dotAnimation = StepTween(begin: 1, end: 3).animate(_controller);

    // auto complete timer
    _completeTimer = Timer(widget.showDuration, () {
      if (!mounted) return;
      _controller.stop();
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _completeTimer?.cancel();
    super.dispose();
  }

  String get dots => '.' * _dotAnimation.value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ================= Card =================
        Container(
          width: 330,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              // ================= Image =================
              Container(
                width: 160,
                height: 190,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  widget.imagePath,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 20),

              // ================= Title + underline =================
              Column(
                children: const [
                  Text(
                    'บทบาทที่ได้รับ',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  SizedBox(height: 4),
                  SizedBox(
                    width: 120,
                    child: Divider(
                      thickness: 1.5,
                      color: Color(0xFF1E1E1E),
                      height: 1,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // ================= Grey Description Box =================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: const [
                    Text(
                      '- aaaa bbbb cccc -',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2A2A2A),
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'aaaa bbbb cccc\n'
                      'aaaa bbbb cccc\n'
                      'aaaa bbbb cccc\n'
                      'aaaa bbbb cccc',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: Color(0xFF4F4F4F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // ================= Waiting Text (Animated) =================
        AnimatedBuilder(
          animation: _dotAnimation,
          builder: (_, __) {
            return Text(
              'รอเวลาสักครู่$dots',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFFBDBDBD),
              ),
            );
          },
        ),
      ],
    );
  }
}
