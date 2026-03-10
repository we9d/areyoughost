import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

class FriendSearchIcon extends StatelessWidget {
  final double size;
  final Color color;

  const FriendSearchIcon({
    super.key,
    this.size = 20,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      BootstrapIcons.search,
      size: size,
      color: color,
    );
  }
}