import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class SendIcon extends StatelessWidget {
  final double size;
  final Color color;

  const SendIcon({
    super.key,
    this.size = 32.0,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      PhosphorIcons.paperPlaneRight(),
      size: size,
      color: color,
    );
  }
}