import 'package:flutter/material.dart';

class NightTimeAnimation extends StatefulWidget {
  const NightTimeAnimation({super.key});

  @override
  State<NightTimeAnimation> createState() => _NightTimeAnimationState();
}

class _NightTimeAnimationState extends State<NightTimeAnimation>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;
  late Animation<double> _animation;

  bool _isVisible = true;

  @override
  void initState() {
    super.initState();

    /// เพิ่มเวลา animation เป็น 6 วินาที
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );

    /// Animation: ขึ้น → หยุด → ลง
    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 500.0, end: -200.0),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -200.0, end: -200.0),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -200.0, end: 500.0),
        weight: 40,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    /// เล่น animation ครั้งเดียว
    _controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: Image.asset(
        "assets/images/moon.png",
        width: 120,
      ),
    );
  }
}