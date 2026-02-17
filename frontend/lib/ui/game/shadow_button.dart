import 'package:flutter/material.dart';

class ShadowButton extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final Gradient? gradient;
  final VoidCallback? onPressed;
  final Widget child;

  const ShadowButton({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    this.gradient,
    this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Base color layer
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
              // Gradient overlay (inner shadow effect)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: gradient,
                    ),
                  ),
                ),
              ),
              // Content
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                ),
                alignment: Alignment.center,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
