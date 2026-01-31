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
    final isDesktop = kIsWeb || 
        (defaultTargetPlatform == TargetPlatform.windows) ||
        (defaultTargetPlatform == TargetPlatform.linux) || 
        (defaultTargetPlatform == TargetPlatform.macOS);

    if (!isDesktop) return child;

    return Scaffold(
      backgroundColor: Colors.black, // Fallback background
      body: Stack(
        children: [
          // Background Image/Gradient for Desktop
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: const DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1509114397022-ed747cca3f65?q=80&w=1935&auto=format&fit=crop'), // Spooky background
                  fit: BoxFit.cover,
                  opacity: 0.3,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF0F2027),
                    const Color(0xFF203A43),
                    const Color(0xFF2C5364),
                  ],
                ),
              ),
            ),
          ),
          
          // Mobile Frame
          Center(
            child: Container(
              width: 390, // Standard Mobile Width
              height: 844, // Standard Mobile Height
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: const Color(0xFF333333),
                  width: 12,
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
                borderRadius: BorderRadius.circular(28), // Inner radius
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
