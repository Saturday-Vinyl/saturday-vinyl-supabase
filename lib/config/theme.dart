import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Saturday! brand colors
class SaturdayColors {
  SaturdayColors._(); // Private constructor to prevent instantiation

  // Brand colors
  static const Color primaryDark = Color(0xFF3F3A34);
  static const Color success = Color(0xFF30AA47);
  static const Color error = Color(0xFFF35345);
  static const Color info = Color(0xFF6AC5F4);
  static const Color secondaryGrey = Color(0xFFB2AAA3);
  static const Color light = Color(0xFFE2DAD0);

  // Additional colors for UI consistency
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
}

/// Saturday! theme configuration
class SaturdayTheme {
  SaturdayTheme._(); // Private constructor to prevent instantiation

  /// Light theme
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,

    // Color scheme
    colorScheme: ColorScheme.light(
      primary: SaturdayColors.primaryDark,
      secondary: SaturdayColors.secondaryGrey,
      error: SaturdayColors.error,
      surface: SaturdayColors.white,
      onPrimary: SaturdayColors.white,
      onSecondary: SaturdayColors.primaryDark,
      onError: SaturdayColors.white,
      onSurface: SaturdayColors.primaryDark,
    ),

    // Scaffold background
    scaffoldBackgroundColor: SaturdayColors.light,

    // AppBar theme
    appBarTheme: AppBarTheme(
      backgroundColor: SaturdayColors.primaryDark,
      foregroundColor: SaturdayColors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.bevan(
        fontSize: 20,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
    ),

    // Text theme
    textTheme: TextTheme(
      // Headlines use Bevan
      displayLarge: GoogleFonts.bevan(
        fontSize: 57,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      displayMedium: GoogleFonts.bevan(
        fontSize: 45,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      displaySmall: GoogleFonts.bevan(
        fontSize: 36,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      headlineLarge: GoogleFonts.bevan(
        fontSize: 32,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      headlineMedium: GoogleFonts.bevan(
        fontSize: 28,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      headlineSmall: GoogleFonts.bevan(
        fontSize: 24,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),

      // Titles use Bevan
      titleLarge: GoogleFonts.bevan(
        fontSize: 22,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      titleMedium: GoogleFonts.bevan(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      titleSmall: GoogleFonts.bevan(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),

      // Body text uses default sans-serif
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.primaryDark,
      ),

      // Labels use default sans-serif
      labelLarge: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: SaturdayColors.primaryDark,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: SaturdayColors.primaryDark,
      ),
      labelSmall: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: SaturdayColors.primaryDark,
      ),
    ),

    // Button theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: SaturdayColors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SaturdayColors.primaryDark,
        side: const BorderSide(color: SaturdayColors.primaryDark, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SaturdayColors.primaryDark,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Input decoration theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SaturdayColors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SaturdayColors.secondaryGrey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SaturdayColors.secondaryGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SaturdayColors.primaryDark, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SaturdayColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: SaturdayColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      labelStyle: const TextStyle(color: SaturdayColors.secondaryGrey),
      hintStyle: const TextStyle(color: SaturdayColors.secondaryGrey),
    ),

    // Card theme
    cardTheme: const CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      color: SaturdayColors.white,
    ),

    // Divider theme
    dividerTheme: const DividerThemeData(
      color: SaturdayColors.secondaryGrey,
      thickness: 1,
      space: 1,
    ),

    // Icon theme
    iconTheme: const IconThemeData(
      color: SaturdayColors.primaryDark,
      size: 24,
    ),
  );

  /// Dark theme (for future use)
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,

    // Color scheme
    colorScheme: ColorScheme.dark(
      primary: SaturdayColors.light,
      secondary: SaturdayColors.secondaryGrey,
      error: SaturdayColors.error,
      surface: SaturdayColors.primaryDark,
      onPrimary: SaturdayColors.primaryDark,
      onSecondary: SaturdayColors.white,
      onError: SaturdayColors.white,
      onSurface: SaturdayColors.white,
    ),

    // Scaffold background
    scaffoldBackgroundColor: SaturdayColors.primaryDark,

    // AppBar theme
    appBarTheme: AppBarTheme(
      backgroundColor: SaturdayColors.black,
      foregroundColor: SaturdayColors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.bevan(
        fontSize: 20,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
    ),

    // Text theme with white text for dark mode
    textTheme: TextTheme(
      displayLarge: GoogleFonts.bevan(
        fontSize: 57,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      displayMedium: GoogleFonts.bevan(
        fontSize: 45,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      displaySmall: GoogleFonts.bevan(
        fontSize: 36,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      headlineLarge: GoogleFonts.bevan(
        fontSize: 32,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      headlineMedium: GoogleFonts.bevan(
        fontSize: 28,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      headlineSmall: GoogleFonts.bevan(
        fontSize: 24,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      titleLarge: GoogleFonts.bevan(
        fontSize: 22,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      titleMedium: GoogleFonts.bevan(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      titleSmall: GoogleFonts.bevan(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: SaturdayColors.white,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: SaturdayColors.white,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: SaturdayColors.white,
      ),
      labelSmall: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: SaturdayColors.white,
      ),
    ),

    // Card theme for dark mode
    cardTheme: const CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      color: Color(0xFF2A2622),
    ),
  );
}
