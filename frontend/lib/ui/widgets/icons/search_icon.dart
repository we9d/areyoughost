import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

class SearchIcon extends StatelessWidget {
  final double size;
  final Color color;

  const SearchIcon({
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