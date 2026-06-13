import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';

/// Legacy brand-color constants.
///
/// Deprecated in favor of `lib/config/tokens/colors.dart`
/// ([SaturdayColorTokens]). These constants are kept at their original values
/// so existing screens compile against the same names while the redesign
/// migrates call sites. New code should consume
/// `SaturdayColorTokens.of(context)` so it picks up the paper/ink palette and
/// dark mode automatically.
class SaturdayColors {
  SaturdayColors._();

  /// Primary dark color - main brand color, text, icons
  static const Color primaryDark = Color(0xFF3F3A34);

  /// Success color - success states, confirmations
  ///
  /// The Saturday constitution bans semantic state colors — surfaces
  /// communicate state with text, position, or motion. Call sites using this
  /// will be migrated as their screens are redesigned.
  static const Color success = Color(0xFF30AA47);

  /// Error color - errors, destructive actions
  ///
  /// See note on [success] — state colors are banned by the constitution.
  static const Color error = Color(0xFFF35345);

  /// Warning color - caution states, warnings
  ///
  /// See note on [success] — state colors are banned by the constitution.
  static const Color warning = Color(0xFFF5A623);

  /// Info color - informational states
  ///
  /// See note on [success] — state colors are banned by the constitution.
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
///
/// Both [lightTheme] and [darkTheme] are built from the same
/// [SaturdayColorTokens] structure, so any token change cascades to both.
///
/// What the constitution forbids — and how this file handles each case:
///
/// - **Semantic state colors** (success-green, error-red, warning-amber)
///   are not used. The Material [ColorScheme.error] slot maps to [ink]
///   because Material requires a value; input error borders use
///   [SaturdayColorTokens.borderStrong] instead of a red.
/// - **Toggles / spinners / snackbars / confirm dialogs** are themed only
///   so leftover call sites don't look broken during the redesign. Each
///   such theme block is marked as transitional. The widgets themselves
///   are removed when their owning screens are migrated.
/// - **No drop shadows** beyond the OS-level scrim. Cards and dialogs use
///   hairline borders ([SaturdayColorTokens.borderQuiet]) for separation.
class SaturdayTheme {
  SaturdayTheme._();

  static final ThemeData lightTheme = _build(
    SaturdayColorTokens.light,
    Brightness.light,
  );

  static final ThemeData darkTheme = _build(
    SaturdayColorTokens.dark,
    Brightness.dark,
  );

  static ThemeData _build(SaturdayColorTokens c, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.ink,
      onPrimary: c.paper,
      secondary: c.inkSecondary,
      onSecondary: c.paper,
      tertiary: c.felt,
      onTertiary: c.paper,
      surface: c.paper,
      onSurface: c.ink,
      surfaceContainerHighest: c.paperElevated,
      onSurfaceVariant: c.inkSecondary,
      outline: c.borderStrong,
      outlineVariant: c.borderQuiet,
      // The constitution bans semantic state colors; Material still
      // requires an error slot, so map it onto ink. Errors communicate via
      // factual text — not red surfaces.
      error: c.ink,
      onError: c.paper,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.paper,
      canvasColor: c.paper,
      dividerColor: c.borderQuiet,

      // App Bar — quiet paper bar, serif title in sentence case.
      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: SaturdayType.section.copyWith(
          fontSize: 20,
          color: c.ink,
        ),
        iconTheme: IconThemeData(color: c.ink, size: 24),
      ),

      // Cards — paperElevated with a quiet hairline. No drop shadow.
      cardTheme: CardThemeData(
        color: c.paperElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.borderQuiet),
        ),
        margin: const EdgeInsets.all(SaturdaySpace.space2),
      ),

      // Buttons — ink fill on paper. No elevation.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.paper,
          padding: const EdgeInsets.symmetric(
            horizontal: SaturdaySpace.space6,
            vertical: SaturdaySpace.space3,
          ),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: SaturdayType.body.copyWith(fontWeight: SaturdayType.medium),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.ink),
          padding: const EdgeInsets.symmetric(
            horizontal: SaturdaySpace.space6,
            vertical: SaturdaySpace.space3,
          ),
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: SaturdayType.body.copyWith(fontWeight: SaturdayType.medium),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.ink,
          padding: const EdgeInsets.symmetric(
            horizontal: SaturdaySpace.space4,
            vertical: SaturdaySpace.space2,
          ),
          textStyle: SaturdayType.body.copyWith(fontWeight: SaturdayType.medium),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.ink,
        foregroundColor: c.paper,
        elevation: 0,
        shape: const CircleBorder(),
      ),

      // Input fields — paperElevated fill, ink focus stroke, no red errors.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.paperElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.borderQuiet),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.borderQuiet),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.ink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.borderStrong),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.ink, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SaturdaySpace.space4,
          vertical: SaturdaySpace.space3,
        ),
        hintStyle: SaturdayType.body.copyWith(color: c.inkTertiary),
        labelStyle: SaturdayType.body.copyWith(color: c.inkSecondary),
        errorStyle: SaturdayType.meta.copyWith(color: c.inkSecondary),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.paperElevated,
        selectedItemColor: c.ink,
        unselectedItemColor: c.inkTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: SaturdayType.meta.copyWith(
          fontWeight: SaturdayType.medium,
        ),
        unselectedLabelStyle: SaturdayType.meta,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.paperElevated,
        indicatorColor: c.borderQuiet,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.ink, size: 24);
          }
          return IconThemeData(color: c.inkTertiary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return SaturdayType.meta.copyWith(
              color: c.ink,
              fontWeight: SaturdayType.medium,
            );
          }
          return SaturdayType.meta.copyWith(color: c.inkTertiary);
        }),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.paperElevated,
        selectedColor: c.ink,
        disabledColor: c.borderQuiet,
        labelStyle: SaturdayType.body.copyWith(color: c.ink),
        secondaryLabelStyle: SaturdayType.body.copyWith(color: c.paper),
        padding: const EdgeInsets.symmetric(
          horizontal: SaturdaySpace.space3,
          vertical: SaturdaySpace.space2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: c.borderQuiet),
        ),
      ),

      // Dialogs — paperElevated card with a hairline. The constitution
      // bans confirmation dialogs before destructive actions (use undo
      // instead); informational dialogs are still allowed.
      dialogTheme: DialogThemeData(
        backgroundColor: c.paperElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.borderQuiet),
        ),
        titleTextStyle: SaturdayType.section.copyWith(
          fontSize: 22,
          color: c.ink,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.paper,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: c.borderStrong,
        dragHandleSize: const Size(32, 4),
        showDragHandle: true,
      ),

      // Snackbars are banned by the constitution — state changes reflect
      // in the surface itself, not in a floating toast. Themed quietly so
      // any leftover call sites don't look obviously broken; removal
      // happens at the call sites during per-screen migration.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: SaturdayType.body.copyWith(color: c.paper),
        actionTextColor: c.paper,
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        closeIconColor: c.paper,
        dismissDirection: DismissDirection.horizontal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      dividerTheme: DividerThemeData(
        color: c.borderQuiet,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.ink,
        textColor: c.ink,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SaturdaySpace.space4,
          vertical: SaturdaySpace.space1,
        ),
      ),

      iconTheme: IconThemeData(color: c.ink, size: 24),

      // Progress indicators are banned by the constitution — loading uses
      // <Skeleton> and content arrives via the `arrive` gesture. Themed
      // quietly so any leftover call sites don't show a Material-default
      // blue spinner; removal happens at the call sites.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.ink,
        linearTrackColor: c.borderQuiet,
        circularTrackColor: c.borderQuiet,
      ),

      // Toggle switches are banned by the constitution — state is text
      // (`off`, `local only`, `connected`), not a switch. Themed quietly
      // so leftover call sites don't look out of place; removal happens
      // at the call sites during per-screen migration.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.ink;
          return c.inkTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return c.ink.withValues(alpha: 0.4);
          }
          return c.borderQuiet;
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.ink;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(c.paper),
        side: BorderSide(color: c.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.ink;
          return c.borderStrong;
        }),
      ),

      textTheme: _textTheme(c),
      primaryTextTheme: _textTheme(c),
    );
  }

  /// Map Material's text-theme slots onto Saturday named tokens so existing
  /// widgets that look up `Theme.of(context).textTheme.bodyMedium` keep
  /// working. Per-screen redesigns can address tokens directly via
  /// [SaturdayType].
  static TextTheme _textTheme(SaturdayColorTokens c) {
    TextStyle ink(TextStyle s) => s.copyWith(color: c.ink);
    TextStyle dim(TextStyle s) => s.copyWith(color: c.inkSecondary);

    return TextTheme(
      // Display / headline — serif scale.
      displayLarge: ink(SaturdayType.titleListening),
      displayMedium: ink(SaturdayType.titleArchive),
      displaySmall: ink(SaturdayType.section),
      headlineLarge: ink(SaturdayType.section),
      headlineMedium: ink(SaturdayType.titleArchive),
      headlineSmall: ink(SaturdayType.section),
      // Titles — sans, medium weight on the larger sizes.
      titleLarge: ink(
        SaturdayType.body.copyWith(
          fontSize: 20,
          fontWeight: SaturdayType.medium,
        ),
      ),
      titleMedium: ink(
        SaturdayType.body.copyWith(fontWeight: SaturdayType.medium),
      ),
      titleSmall: ink(
        SaturdayType.bodySmall.copyWith(fontWeight: SaturdayType.medium),
      ),
      // Body.
      bodyLarge: ink(SaturdayType.body.copyWith(fontSize: 16)),
      bodyMedium: ink(SaturdayType.body),
      bodySmall: dim(SaturdayType.meta),
      // Labels.
      labelLarge: ink(
        SaturdayType.body.copyWith(fontWeight: SaturdayType.medium),
      ),
      labelMedium: ink(
        SaturdayType.meta.copyWith(fontWeight: SaturdayType.medium),
      ),
      labelSmall: dim(SaturdayType.eyebrow),
    );
  }
}
