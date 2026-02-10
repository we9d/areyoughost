/// Mobile Wrapper Widget
///
/// This widget creates a desktop-optimized UI by displaying the app
/// in a mobile-like frame (390x844) centered on the desktop screen.
///
/// Features:
/// - Only applies on desktop platforms (Windows/macOS/Linux/Web)
/// - Shows a spooky background gradient and image
/// - Creates a phone-like frame with rounded corners and shadow
/// - Passes through on actual mobile devices
///
/// This approach allows for a consistent mobile-first design while
/// providing an enhanced desktop experience.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Wraps the app content in a mobile-sized frame on desktop platforms
///
/// The wrapper displays a 390x844 centered frame with a decorative
/// background, creating a mobile app aesthetic on desktop.
class MobileWrapper extends StatelessWidget {
  final Widget child;

  const MobileWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Only apply wrapper on web/desktop, not on actual mobile devices
    final isDesktop =
        kIsWeb ||
        (defaultTargetPlatform == TargetPlatform.windows) ||
        (defaultTargetPlatform == TargetPlatform.linux) ||
        (defaultTargetPlatform == TargetPlatform.macOS);

    if (!isDesktop) return child;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: const DecorationImage(
                  image: NetworkImage(
                    'https://i.pinimg.com/736x/fd/0d/45/fd0d45e403f966860c73fe08efd651d6.jpg',
                  ),
                  fit: BoxFit.cover,
                  opacity: 0.3,
                ),
              ),
            ),
          ),

          // Mobile Frame (แก้เฉพาะส่วนนี้ให้ใช้ aspect ratio)
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double designWidth = 390;
                const double designHeight = 844;
                final double aspectRatio = designWidth / designHeight;

                double width = constraints.maxWidth;
                double height = width / aspectRatio;

                if (height > constraints.maxHeight) {
                  height = constraints.maxHeight;
                  width = height * aspectRatio;
                }

                return Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: const Color.fromARGB(255, 0, 0, 0),
                      width: 10,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: child,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
