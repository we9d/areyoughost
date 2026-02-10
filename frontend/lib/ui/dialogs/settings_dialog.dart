import 'package:areyoughost/ui/dialogs/change_username_dialog.dart';
import 'package:areyoughost/ui/home/home.dart';
import 'package:areyoughost/ui/widgets/buttons/logout_buttons.dart';
import 'package:areyoughost/ui/widgets/settings_title.dart';
import 'package:areyoughost/ui/widgets/username_field.dart';
import 'package:areyoughost/ui/widgets/volume_slider.dart';
import 'package:flutter/material.dart';
import 'package:areyoughost/ui/widgets/buttons/login_buttons.dart';

class SettingsIcon extends StatelessWidget {
  final IconData icon;
  const SettingsIcon({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(icon, color: Colors.white, size: 25),
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

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  static const double dialogWidth = 358;
  static const double dialogHeight = 330;

  double backgroundMusicVolume = 0.5;
  bool canEditUsername = false;

  final TextEditingController usernameController = TextEditingController(
    text: 'ยังไม่ได้ทำการเข้าสู่ระบบ',
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Stack(
          children: [
            _closeButton(context),
            const SettingsTitle(),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UsernameField(
                    controller: usernameController,
                    canEdit: false,
                    onEditPressed: () {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => ChangeUsernameDialog(
                          controller: usernameController,
                        ),
                      );
                    }, 
                  ),

                  const SizedBox(height: 20),

                  VolumeSlider(
                    value: backgroundMusicVolume,
                    onChanged: (value) {
                      setState(() {
                        backgroundMusicVolume = value;
                      });
                    },
                  ),

                  const Spacer(),

                  Center(
                    child: LogoutButton(
                      // onPressed: () => Navigator.push(
                      //   context,
                      //   MaterialPageRoute(builder: (_) => const HomeScreen()),
                      // ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closeButton(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: IconButton(
        icon: const Icon(Icons.close, size: 20, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}
