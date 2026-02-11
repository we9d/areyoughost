import 'package:flutter/material.dart';

/// A custom button with inner shadow effect used throughout the authentication flow.
/// 
/// This button features a golden yellow background with an inner shadow effect
/// to create a pressed/embossed appearance.
class AuthButton extends StatelessWidget {
  /// The text to display on the button
  final String text;
  
  /// Callback function when the button is tapped
  final VoidCallback onTap;
  
  /// Optional custom width (defaults to 172)
  final double? width;
  
  /// Optional custom height (defaults to 40)
  final double? height;

  const AuthButton({
    super.key,
    required this.text,
    required this.onTap,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 172,
      height: height ?? 40,
      child: Stack(
        children: [
          // Background container with golden color
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1C232),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          // Inner shadow effect
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              painter: _InnerShadowPainter(),
              child: Container(),
            ),
          ),
          // Clickable overlay with text
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Center(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontFamily: 'Charmonman',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter that creates an inner shadow effect for the AuthButton.
class _InnerShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final paint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(1),
        const Radius.circular(14),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
