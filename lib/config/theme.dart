import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Saturday brand colors.
class SaturdayColors {
  SaturdayColors._();

  /// Primary dark color - main brand color, text, icons
  static const Color primaryDark = Color(0xFF3F3A34);

  /// Success color - success states, confirmations
  static const Color success = Color(0xFF30AA47);

  /// Error color - errors, destructive actions
  static const Color error = Color(0xFFF35345);

  /// Info color - informational states
  static const Color info = Color(0xFF6AC5F4);

  /// Secondary color - secondary text, borders
  static const Color secondary = Color(0xFFB2AAA3);

  /// Light color - backgrounds, cards
  static const Color light = Color(0xFFE2DAD0);

  /// White for contrast
  static const Color white = Colors.white;

  /// Black for high contrast text
  static const Color black = Color(0xFF1A1A1A);
}

/// Saturday theme configuration.
class SaturdayTheme {
  SaturdayTheme._();

  /// Bevan text style for headlines (blocky serif, retro feel).
  static TextStyle _bevanStyle({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color color = SaturdayColors.primaryDark,
  }) {
    return GoogleFonts.bevan(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  /// Light theme for the app.
  static ThemeData get lightTheme {
    // Base text theme with system font
    final baseTextTheme = ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: SaturdayColors.primaryDark,
        brightness: Brightness.light,
        primary: SaturdayColors.primaryDark,
        secondary: SaturdayColors.secondary,
        surface: SaturdayColors.light,
        error: SaturdayColors.error,
        onPrimary: SaturdayColors.white,
        onSecondary: SaturdayColors.primaryDark,
        onSurface: SaturdayColors.primaryDark,
        onError: SaturdayColors.white,
      ),
      scaffoldBackgroundColor: SaturdayColors.light,

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: SaturdayColors.light,
        foregroundColor: SaturdayColors.primaryDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _bevanStyle(fontSize: 20),
        iconTheme: const IconThemeData(
          color: SaturdayColors.primaryDark,
          size: 24,
        ),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: SaturdayColors.white,
        elevation: 2,
        shadowColor: SaturdayColors.primaryDark.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.all(8),
      ),

      // Elevated Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SaturdayColors.primaryDark,
          foregroundColor: SaturdayColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          elevation: 2,
        ),
      ),

      // Outlined Buttons
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SaturdayColors.primaryDark,
          side: const BorderSide(
            color: SaturdayColors.primaryDark,
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text Buttons
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SaturdayColors.primaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Floating Action Buttons
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: SaturdayColors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SaturdayColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SaturdayColors.secondary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SaturdayColors.secondary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SaturdayColors.primaryDark,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: SaturdayColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SaturdayColors.error,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: const TextStyle(
          color: SaturdayColors.secondary,
          fontSize: 16,
        ),
        labelStyle: const TextStyle(
          color: SaturdayColors.primaryDark,
          fontSize: 16,
        ),
        errorStyle: const TextStyle(
          color: SaturdayColors.error,
          fontSize: 12,
        ),
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: SaturdayColors.white,
        selectedItemColor: SaturdayColors.primaryDark,
        unselectedItemColor: SaturdayColors.secondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
      ),

      // Navigation Bar (Material 3)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SaturdayColors.white,
        indicatorColor: SaturdayColors.light,
        elevation: 8,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: SaturdayColors.primaryDark,
              size: 24,
            );
          }
          return const IconThemeData(
            color: SaturdayColors.secondary,
            size: 24,
          );
        }),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: SaturdayColors.white,
        selectedColor: SaturdayColors.primaryDark,
        disabledColor: SaturdayColors.secondary.withValues(alpha: 0.3),
        labelStyle: const TextStyle(
          color: SaturdayColors.primaryDark,
          fontSize: 14,
        ),
        secondaryLabelStyle: const TextStyle(
          color: SaturdayColors.white,
          fontSize: 14,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: SaturdayColors.secondary),
        ),
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: SaturdayColors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: _bevanStyle(fontSize: 20),
      ),

      // Bottom Sheets
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SaturdayColors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: SaturdayColors.secondary,
        dragHandleSize: Size(32, 4),
        showDragHandle: true,
      ),

      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SaturdayColors.primaryDark,
        contentTextStyle: const TextStyle(
          color: SaturdayColors.white,
          fontSize: 14,
        ),
        actionTextColor: SaturdayColors.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: SaturdayColors.secondary,
        thickness: 1,
        space: 1,
      ),

      // List Tiles
      listTileTheme: const ListTileThemeData(
        iconColor: SaturdayColors.primaryDark,
        textColor: SaturdayColors.primaryDark,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      // Icon theme
      iconTheme: const IconThemeData(
        color: SaturdayColors.primaryDark,
        size: 24,
      ),

      // Progress Indicators
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SaturdayColors.primaryDark,
        linearTrackColor: SaturdayColors.secondary,
        circularTrackColor: SaturdayColors.secondary,
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SaturdayColors.primaryDark;
          }
          return SaturdayColors.secondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SaturdayColors.primaryDark.withValues(alpha: 0.5);
          }
          return SaturdayColors.secondary.withValues(alpha: 0.3);
        }),
      ),

      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SaturdayColors.primaryDark;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(SaturdayColors.white),
        side: const BorderSide(color: SaturdayColors.secondary, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),

      // Radio
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SaturdayColors.primaryDark;
          }
          return SaturdayColors.secondary;
        }),
      ),

      // Text Theme - Bevan for headlines, system font for body
      textTheme: TextTheme(
        // Display styles (large headers)
        displayLarge: _bevanStyle(fontSize: 57),
        displayMedium: _bevanStyle(fontSize: 45),
        displaySmall: _bevanStyle(fontSize: 36),

        // Headline styles (section headers)
        headlineLarge: _bevanStyle(fontSize: 32),
        headlineMedium: _bevanStyle(fontSize: 28),
        headlineSmall: _bevanStyle(fontSize: 24),

        // Title styles (card titles, etc.)
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: SaturdayColors.primaryDark,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: SaturdayColors.primaryDark,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: SaturdayColors.primaryDark,
        ),

        // Body styles (main content)
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: 16,
          color: SaturdayColors.primaryDark,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 14,
          color: SaturdayColors.primaryDark,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: SaturdayColors.secondary,
        ),

        // Label styles (buttons, inputs)
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: SaturdayColors.primaryDark,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: SaturdayColors.primaryDark,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }
}
