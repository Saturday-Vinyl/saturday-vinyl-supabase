import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:saturday_app/config/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock font loading to avoid network calls in tests
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('SaturdayColors', () {
    test('all brand colors are correctly defined', () {
      expect(SaturdayColors.primaryDark, const Color(0xFF3F3A34));
      expect(SaturdayColors.success, const Color(0xFF30AA47));
      expect(SaturdayColors.error, const Color(0xFFF35345));
      expect(SaturdayColors.info, const Color(0xFF6AC5F4));
      expect(SaturdayColors.secondaryGrey, const Color(0xFFB2AAA3));
      expect(SaturdayColors.light, const Color(0xFFE2DAD0));
      expect(SaturdayColors.white, const Color(0xFFFFFFFF));
      expect(SaturdayColors.black, const Color(0xFF000000));
    });

    test('colors are distinct from each other', () {
      final colors = [
        SaturdayColors.primaryDark,
        SaturdayColors.success,
        SaturdayColors.error,
        SaturdayColors.info,
        SaturdayColors.secondaryGrey,
        SaturdayColors.light,
      ];

      // Check that all colors are unique
      final uniqueColors = colors.toSet();
      expect(uniqueColors.length, colors.length);
    });
  });

  group('SaturdayTheme.lightTheme', () {
    late ThemeData theme;

    setUp(() {
      // Access theme once per group to avoid multiple font loads
      theme = SaturdayTheme.lightTheme;
    });

    test('theme data is not null', () {
      expect(theme, isNotNull);
    });

    test('uses Material 3', () {
      expect(theme.useMaterial3, true);
    });

    test('color scheme uses brand colors', () {
      final colorScheme = theme.colorScheme;
      expect(colorScheme.primary, SaturdayColors.primaryDark);
      expect(colorScheme.secondary, SaturdayColors.secondaryGrey);
      expect(colorScheme.error, SaturdayColors.error);
    });

    test('scaffold background color is light', () {
      expect(
        theme.scaffoldBackgroundColor,
        SaturdayColors.light,
      );
    });

    test('app bar uses primary dark background', () {
      expect(
        theme.appBarTheme.backgroundColor,
        SaturdayColors.primaryDark,
      );
      expect(
        theme.appBarTheme.foregroundColor,
        SaturdayColors.white,
      );
    });

    test('text theme headlines use Bevan font', () {
      final textTheme = theme.textTheme;

      // Check that headline fonts contain 'Bevan' (may be 'Bevan_regular' or just 'Bevan')
      final displayFont = textTheme.displayLarge?.fontFamily?.toLowerCase() ?? '';
      final headlineFont = textTheme.headlineLarge?.fontFamily?.toLowerCase() ?? '';
      final titleFont = textTheme.titleLarge?.fontFamily?.toLowerCase() ?? '';

      expect(displayFont, contains('bevan'));
      expect(headlineFont, contains('bevan'));
      expect(titleFont, contains('bevan'));
    });

    test('text theme body text uses default sans-serif', () {
      final textTheme = theme.textTheme;

      // Body text should not specify Bevan font (uses default or null)
      final bodyLargeFont = textTheme.bodyLarge?.fontFamily?.toLowerCase();
      final bodyMediumFont = textTheme.bodyMedium?.fontFamily?.toLowerCase();

      expect(bodyLargeFont, isNot(contains('bevan')));
      expect(bodyMediumFont, isNot(contains('bevan')));
    });

    test('elevated button uses primary dark background', () {
      final buttonStyle = theme.elevatedButtonTheme.style;
      final backgroundColor = buttonStyle?.backgroundColor?.resolve({});
      expect(backgroundColor, SaturdayColors.primaryDark);
    });

    test('card theme has proper elevation and shape', () {
      final cardTheme = theme.cardTheme;
      expect(cardTheme.elevation, 2);
      expect(cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(cardTheme.color, SaturdayColors.white);
    });

    test('input decoration has proper styling', () {
      final inputTheme = theme.inputDecorationTheme;
      expect(inputTheme.filled, true);
      expect(inputTheme.fillColor, SaturdayColors.white);
      expect(inputTheme.border, isA<OutlineInputBorder>());
    });
  });

  group('SaturdayTheme.darkTheme', () {
    late ThemeData darkTheme;

    setUp(() {
      darkTheme = SaturdayTheme.darkTheme;
    });

    test('theme data is not null', () {
      expect(darkTheme, isNotNull);
    });

    test('uses Material 3', () {
      expect(darkTheme.useMaterial3, true);
    });

    test('scaffold background color is dark', () {
      expect(
        darkTheme.scaffoldBackgroundColor,
        SaturdayColors.primaryDark,
      );
    });

    test('color scheme uses inverted colors', () {
      final colorScheme = darkTheme.colorScheme;
      expect(colorScheme.primary, SaturdayColors.light);
      expect(colorScheme.surface, SaturdayColors.primaryDark);
    });

    test('text colors are white for visibility', () {
      final textTheme = darkTheme.textTheme;
      expect(textTheme.bodyLarge?.color, SaturdayColors.white);
      expect(textTheme.headlineLarge?.color, SaturdayColors.white);
    });
  });

  group('Theme consistency', () {
    test('light and dark themes have matching text styles', () {
      final lightTheme = SaturdayTheme.lightTheme;
      final darkTheme = SaturdayTheme.darkTheme;

      // Font sizes should match between themes
      expect(
        lightTheme.textTheme.displayLarge?.fontSize,
        darkTheme.textTheme.displayLarge?.fontSize,
      );
      expect(
        lightTheme.textTheme.bodyLarge?.fontSize,
        darkTheme.textTheme.bodyLarge?.fontSize,
      );
    });

    test('both themes use the same font family for headlines', () {
      final lightTheme = SaturdayTheme.lightTheme;
      final darkTheme = SaturdayTheme.darkTheme;

      final lightFont = lightTheme.textTheme.displayLarge?.fontFamily?.toLowerCase();
      final darkFont = darkTheme.textTheme.displayLarge?.fontFamily?.toLowerCase();

      // Both should use Bevan
      expect(lightFont, contains('bevan'));
      expect(darkFont, contains('bevan'));
    });
  });
}
