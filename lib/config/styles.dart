import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// Spacing constants for consistent layout throughout the app.
///
/// Use these values for padding, margins, and gaps to maintain
/// visual consistency across all screens.
class Spacing {
  Spacing._();

  /// Extra small spacing (4px)
  static const double xs = 4;

  /// Small spacing (8px)
  static const double sm = 8;

  /// Medium spacing (12px)
  static const double md = 12;

  /// Large spacing (16px)
  static const double lg = 16;

  /// Extra large spacing (24px)
  static const double xl = 24;

  /// Double extra large spacing (32px)
  static const double xxl = 32;

  /// Triple extra large spacing (48px)
  static const double xxxl = 48;

  /// Standard page padding
  static const EdgeInsets pagePadding = EdgeInsets.all(lg);

  /// Horizontal page padding only
  static const EdgeInsets pageHorizontal = EdgeInsets.symmetric(horizontal: lg);

  /// Card content padding
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  /// List item padding
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );

  /// Section spacing (vertical gap between sections)
  static const SizedBox sectionGap = SizedBox(height: xl);

  /// Item spacing (vertical gap between items in a list)
  static const SizedBox itemGap = SizedBox(height: md);

  /// Small horizontal gap
  static const SizedBox horizontalGapSm = SizedBox(width: sm);

  /// Medium horizontal gap
  static const SizedBox horizontalGapMd = SizedBox(width: md);

  /// Large horizontal gap
  static const SizedBox horizontalGapLg = SizedBox(width: lg);
}

/// Border radius constants for consistent styling.
class AppRadius {
  AppRadius._();

  /// Small radius (8px) - for small elements like chips
  static const double sm = 8;

  /// Medium radius (12px) - for buttons, inputs
  static const double md = 12;

  /// Large radius (16px) - for cards
  static const double lg = 16;

  /// Extra large radius (24px) - for bottom sheets, modals
  static const double xl = 24;

  /// Full radius for circular elements
  static const double full = 999;

  /// Small border radius
  static BorderRadius get smallRadius => BorderRadius.circular(sm);

  /// Medium border radius
  static BorderRadius get mediumRadius => BorderRadius.circular(md);

  /// Large border radius
  static BorderRadius get largeRadius => BorderRadius.circular(lg);

  /// Extra large border radius
  static BorderRadius get extraLargeRadius => BorderRadius.circular(xl);

  /// Circular border radius
  static BorderRadius get circularRadius => BorderRadius.circular(full);

  /// Top-only large radius for bottom sheets
  static BorderRadius get topLargeRadius => const BorderRadius.vertical(
        top: Radius.circular(xl),
      );
}

/// Shadow definitions for consistent elevation.
class AppShadows {
  AppShadows._();

  /// Subtle shadow for cards
  static List<BoxShadow> get card => [
        BoxShadow(
          color: SaturdayColors.primaryDark.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// Medium shadow for elevated elements
  static List<BoxShadow> get elevated => [
        BoxShadow(
          color: SaturdayColors.primaryDark.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// Strong shadow for modals and overlays
  static List<BoxShadow> get modal => [
        BoxShadow(
          color: SaturdayColors.primaryDark.withValues(alpha: 0.16),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

/// Animation durations for consistent motion.
class AppDurations {
  AppDurations._();

  /// Fast animation (150ms) - for micro-interactions
  static const Duration fast = Duration(milliseconds: 150);

  /// Normal animation (250ms) - for standard transitions
  static const Duration normal = Duration(milliseconds: 250);

  /// Slow animation (400ms) - for page transitions
  static const Duration slow = Duration(milliseconds: 400);
}

/// Common icon sizes.
class AppIconSizes {
  AppIconSizes._();

  /// Small icon (16px)
  static const double sm = 16;

  /// Medium icon (20px)
  static const double md = 20;

  /// Large icon (24px) - default
  static const double lg = 24;

  /// Extra large icon (32px)
  static const double xl = 32;

  /// Hero icon (48px)
  static const double hero = 48;

  /// Feature icon (64px)
  static const double feature = 64;
}

/// Album art sizes for consistent display.
class AlbumArtSizes {
  AlbumArtSizes._();

  /// Thumbnail size (48x48)
  static const double thumbnail = 48;

  /// Small size (80x80)
  static const double small = 80;

  /// Medium size (120x120)
  static const double medium = 120;

  /// Large size (200x200)
  static const double large = 200;

  /// Hero size (full width, square)
  static const double hero = double.infinity;
}

/// Reusable decorations.
class AppDecorations {
  AppDecorations._();

  /// Standard card decoration
  static BoxDecoration get card => BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
      );

  /// Elevated card decoration
  static BoxDecoration get elevatedCard => BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.elevated,
      );

  /// Album art decoration with rounded corners
  static BoxDecoration get albumArt => BoxDecoration(
        borderRadius: AppRadius.largeRadius,
        color: SaturdayColors.secondary.withValues(alpha: 0.2),
      );

  /// Circular avatar decoration
  static BoxDecoration get avatar => const BoxDecoration(
        shape: BoxShape.circle,
        color: SaturdayColors.secondary,
      );
}
