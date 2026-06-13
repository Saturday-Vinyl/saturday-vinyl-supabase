import 'package:flutter/material.dart';

/// Saturday color tokens.
///
/// Defined in `shared-docs/foundation/constitution.md` (Tokens → Color). The
/// system has no color of its own — surfaces are paper/ink with hairline
/// borders. Album-derived atmospheric color belongs in listening surfaces only;
/// the felt orange is reserved for identity moments.
///
/// Rules from the constitution worth remembering when consuming these tokens:
///
/// - No semantic state colors (no success-green, error-red, warning-amber).
///   State is communicated by text, position, or motion.
/// - The archive uses paper/ink only. Never album-derived color.
/// - Felt orange and album-derived color never appear on the same screen.
/// - Hardcoded color values are not allowed in feature code.
///
/// Light/dark sets resolve via [SaturdayColorTokens.of] using the ambient
/// [Theme]'s brightness.
@immutable
class SaturdayColorTokens {
  const SaturdayColorTokens({
    required this.paper,
    required this.paperElevated,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.borderQuiet,
    required this.borderStrong,
    required this.felt,
  });

  /// Body background.
  final Color paper;

  /// Cards and raised surfaces.
  final Color paperElevated;

  /// Primary text.
  final Color ink;

  /// Secondary text and metadata.
  final Color inkSecondary;

  /// Tertiary text, captions, and hints.
  final Color inkTertiary;

  /// Hairlines and dividers.
  final Color borderQuiet;

  /// Stronger divisions.
  final Color borderStrong;

  /// Identity-moment accent. Working placeholder pending physical
  /// measurement against the actual orange felt.
  final Color felt;

  static const SaturdayColorTokens light = SaturdayColorTokens(
    paper: Color(0xFFF6F5F2),
    paperElevated: Color(0xFFFFFFFF),
    ink: Color(0xFF1A1817),
    inkSecondary: Color(0xFF5A5854),
    inkTertiary: Color(0xFF8A8884),
    borderQuiet: Color(0xFFE8E6E0),
    borderStrong: Color(0xFFC8C6C0),
    felt: Color(0xFFC25A2A),
  );

  static const SaturdayColorTokens dark = SaturdayColorTokens(
    paper: Color(0xFF1A1817),
    paperElevated: Color(0xFF232120),
    ink: Color(0xFFF4F2EC),
    inkSecondary: Color(0xFFB4B2AC),
    inkTertiary: Color(0xFF7A7874),
    borderQuiet: Color(0xFF2A2826),
    borderStrong: Color(0xFF3F3D3A),
    felt: Color(0xFFC25A2A),
  );

  /// Resolve the token set for the current [Theme] brightness.
  static SaturdayColorTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  /// Resolve the token set for an explicit [brightness].
  static SaturdayColorTokens forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }
}
