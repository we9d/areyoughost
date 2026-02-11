import 'package:flutter/material.dart';

/// A success dialog widget used after successful authentication actions.
/// 
/// Displays a success icon, title, and message, then automatically dismisses
/// and navigates to the specified destination.
class SuccessDialog extends StatelessWidget {
  /// The title text to display
  final String title;
  
  /// The message text to display
  final String message;
  
  /// The widget to navigate to after dismissal
  final Widget destination;
  
  /// Duration before auto-dismiss (defaults to 1 second)
  final Duration duration;

  const SuccessDialog({
    super.key,
    required this.title,
    required this.message,
    required this.destination,
    this.duration = const Duration(seconds: 1),
  });

  /// Show the success dialog and auto-navigate
  static void show({
    required BuildContext context,
    required String title,
    required String message,
    required Widget destination,
    Duration duration = const Duration(seconds: 1),
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Auto-dismiss and navigate after duration
        Future.delayed(duration, () {
          if (Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => destination),
          );
        });

        return SuccessDialog(
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon
            const CircleAvatar(
              radius: 32,
              backgroundColor: Color(0xFF018A0C),
              child: Icon(Icons.check, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Charmonman',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            // Message
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Charmonman',
                fontSize: 14,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
