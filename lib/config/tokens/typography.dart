import 'package:flutter/material.dart';

/// Saturday type tokens.
///
/// Three families and two weights only (Regular 400, Medium 500), per
/// `shared-docs/foundation/constitution.md` (Tokens → Type).
///
/// Family names are the working picks — they will fall back to the system
/// font until the font assets are bundled (planned in step 3 of the redesign).
/// The production candidates are Söhne, Tiempos Text, and Söhne Mono (Klim).
///
/// Rules from the constitution worth remembering when consuming these tokens:
///
/// - Album titles render in serif italic in body text. Artist names render
///   in sans.
/// - Sentence case throughout. No Title Case. No ALL CAPS (except mono
///   technical data sourced as-is — matrix numbers, catalog labels).
class SaturdayType {
  SaturdayType._();

  // ---------------------------------------------------------------------------
  // Families
  // ---------------------------------------------------------------------------

  /// UI chrome, labels, metadata. Working pick: Inter Tight.
  static const String fontSans = 'Inter Tight';

  /// Album titles, narrative, witness. Working pick: Source Serif 4.
  static const String fontSerif = 'Source Serif 4';

  /// Matrix numbers, timings, gear chain. Working pick: JetBrains Mono.
  static const String fontMono = 'JetBrains Mono';

  // ---------------------------------------------------------------------------
  // Weights
  // ---------------------------------------------------------------------------

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;

  // ---------------------------------------------------------------------------
  // Line heights (from foundations §4.3, encoded in the constitution)
  // ---------------------------------------------------------------------------

  /// Serif body and witness narrative.
  static const double lineSerifBody = 1.65;

  /// Sans body.
  static const double lineSansBody = 1.5;

  /// Sans labels and metadata.
  static const double lineSansLabel = 1.35;

  /// Mono technical data.
  static const double lineMono = 1.4;

  // ---------------------------------------------------------------------------
  // Named text tokens
  //
  // Working scale from the constitution. Not yet canonized in foundations §3 —
  // revisit when building components.
  // ---------------------------------------------------------------------------

  /// 11 / sans — wayfinding labels, section eyebrows.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: fontSans,
    fontSize: 11,
    fontWeight: medium,
    height: lineSansLabel,
  );

  /// 12 / sans — metadata, captions.
  static const TextStyle meta = TextStyle(
    fontFamily: fontSans,
    fontSize: 12,
    fontWeight: regular,
    height: lineSansLabel,
  );

  /// 13 / sans — UI prose, helper text.
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontSans,
    fontSize: 13,
    fontWeight: regular,
    height: lineSansBody,
  );

  /// 14 / sans — UI body.
  static const TextStyle body = TextStyle(
    fontFamily: fontSans,
    fontSize: 14,
    fontWeight: regular,
    height: lineSansBody,
  );

  /// 14 / serif — archive narrative body.
  static const TextStyle bodySerif = TextStyle(
    fontFamily: fontSerif,
    fontSize: 14,
    fontWeight: regular,
    height: lineSerifBody,
  );

  /// 17 / serif — long-form witness narrative.
  static const TextStyle prose = TextStyle(
    fontFamily: fontSerif,
    fontSize: 17,
    fontWeight: regular,
    height: lineSerifBody,
  );

  /// 26 / serif — section headings.
  static const TextStyle section = TextStyle(
    fontFamily: fontSerif,
    fontSize: 26,
    fontWeight: regular,
    height: 1.25,
  );

  /// 28 / serif — archive page titles.
  static const TextStyle titleArchive = TextStyle(
    fontFamily: fontSerif,
    fontSize: 28,
    fontWeight: regular,
    height: 1.2,
  );

  /// 38 / serif — listening-room album titles.
  static const TextStyle titleListening = TextStyle(
    fontFamily: fontSerif,
    fontSize: 38,
    fontWeight: regular,
    height: 1.15,
  );

  /// Mono technical data — matrix numbers, timings, gear chain.
  static const TextStyle mono = TextStyle(
    fontFamily: fontMono,
    fontSize: 13,
    fontWeight: regular,
    height: lineMono,
  );
}
