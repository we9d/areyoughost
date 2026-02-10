import 'package:flutter/material.dart';
import 'package:areyoughost/ui/dialogs/settings_dialog.dart';

class SettingsIcon extends StatelessWidget {
  final IconData icon;

  const SettingsIcon({
    super.key,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(
        icon,
        color: Colors.white,
        size: 25,
      ),
      onPressed: () {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const SettingsDialog(),
        );
      },
    );
  }
}
