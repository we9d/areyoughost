import 'package:flutter/material.dart';

class NetworkOrAssetImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Widget? fallback;
  final Alignment alignment;

  const NetworkOrAssetImage({
    super.key,
    required this.path,
    this.fit = BoxFit.contain,
    this.fallback,
    this.alignment = Alignment.center,
  });

  bool get _isNetworkPath {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') || p.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    if (_isNetworkPath) {
      return Image.network(
        path,
        fit: fit,
        alignment: alignment,
        errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
      );
    }
    return Image.asset(
      path,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
    );
  }
}
