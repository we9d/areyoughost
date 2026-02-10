import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1A1A2E), // Deep dark blue
    colorScheme: const ColorScheme.dark(
      // primary: Color(0xFFE94560), // Energetic red/pink
      // secondary: Color(0xFF0F3460), // Secondary dark blue
      // surface: Color(0xFF16213E),
      // onPrimary: Colors.white,
      // onSecondary: Colors.white,
      // onSurface: Colors.white,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Colors.black, // สี cursor
      selectionColor: Color.fromARGB(255, 129, 129, 129), // สีพื้นหลังตอนลากเลือก
      selectionHandleColor: Color.fromARGB(255, 129, 129, 129), // สีปุ่มหยดน้ำ
    ),
    fontFamily: 'Charmonman',
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Charmonman'),
    cardTheme: CardThemeData(
      color: const Color(0xFF16213E),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1A2E),
      elevation: 0,
      centerTitle: true,
      // titleTextStyle: const TextStyle(
      //   fontFamily: 'Charmonman',
      //   fontSize: 24,
      //   color: Colors.white,
      // ),
    ),
    // inputDecorationTheme: InputDecorationTheme(
    //   filled: true,
    //   fillColor: const Color(0xFF0F3460),
    //   border: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(12),
    //     borderSide: BorderSide.none,
    //   ),
    //   enabledBorder: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(12),
    //     borderSide: BorderSide.none,
    //   ),
    //   focusedBorder: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(12),
    //     borderSide: const BorderSide(color: Color(0xFFE94560), width: 2),
    //   ),
    //   hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
    // ),
    // elevatedButtonTheme: ElevatedButtonThemeData(
    //   style: ElevatedButton.styleFrom(
    //     minimumSize: const Size(150, 51),
    //     backgroundColor: const Color(0xFF3A5A7A),
    //     foregroundColor: Colors.white,
    //     elevation: 18,
    //     shadowColor: Colors.black.withOpacity(0.6),
    //     padding: const EdgeInsets.symmetric(vertical: 13),
    //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
    //     textStyle: const TextStyle(
    //       fontSize: 24,
    //       fontWeight: FontWeight.bold,
    //       fontFamily: 'Charmonman',
    //     ),
    //   ),
    // ),
  );
}
