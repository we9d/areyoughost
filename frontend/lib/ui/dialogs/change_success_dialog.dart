import 'package:flutter/material.dart';

class ChangeSuccessDialog extends StatelessWidget {
  final String title;
  final String message;
  final Widget destination;
  final Duration duration;

  const ChangeSuccessDialog({
    super.key,
    required this.title,
    required this.message,
    required this.destination,
    this.duration = const Duration(seconds: 2),
  });

  static void show({
    required BuildContext context,
    required String title,
    required String message,
    required Widget destination,
    Duration duration = const Duration(seconds: 2),
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        Future.delayed(duration, () {
          if (Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
          }

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => destination),
          );
        });

        return ChangeSuccessDialog(
          title: title,
          message: message,
          destination: destination,
          duration: duration,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: 358,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 34,
              backgroundColor: Color(0xFF0A9B1E),
              child: Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Charmonman',
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                decoration: TextDecoration.underline,
                decorationColor: Colors.black,
                decorationThickness: 1.2,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Charmonman',
                fontSize: 18,
                color: Color(0xFF444444),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}