import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Extracted color palette from an album's cover art.
///
/// Colors are classified into two groups:
/// - [light] — colors with sufficient luminance for LED display
/// - [dark] — colors that appear too dim on LEDs but work well in UI
///
/// Named colors ([dominant], [vibrant], etc.) map directly to
/// PaletteGenerator output for convenient access.
class AlbumColors extends Equatable {
  final String? dominant;
  final String? vibrant;
  final String? lightVibrant;
  final String? darkVibrant;
  final String? muted;
  final String? lightMuted;
  final String? darkMuted;

  /// Colors with relative luminance >= threshold (LED-safe).
  final List<String> light;

  /// Colors below the luminance threshold (UI only).
  final List<String> dark;

  const AlbumColors({
    this.dominant,
    this.vibrant,
    this.lightVibrant,
    this.darkVibrant,
    this.muted,
    this.lightMuted,
    this.darkMuted,
    this.light = const [],
    this.dark = const [],
  });

  /// Parse a hex color string (#rrggbb) to a Flutter [Color].
  /// Returns null if the string is null or malformed.
  static Color? parseHex(String? hex) {
    if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return null;
    return Color(value | 0xFF000000);
  }

  factory AlbumColors.fromJson(Map<String, dynamic> json) {
    return AlbumColors(
      dominant: json['dominant'] as String?,
      vibrant: json['vibrant'] as String?,
      lightVibrant: json['lightVibrant'] as String?,
      darkVibrant: json['darkVibrant'] as String?,
      muted: json['muted'] as String?,
      lightMuted: json['lightMuted'] as String?,
      darkMuted: json['darkMuted'] as String?,
      light: (json['light'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      dark: (json['dark'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dominant': dominant,
      'vibrant': vibrant,
      'lightVibrant': lightVibrant,
      'darkVibrant': darkVibrant,
      'muted': muted,
      'lightMuted': lightMuted,
      'darkMuted': darkMuted,
      'light': light,
      'dark': dark,
    };
  }

  @override
  List<Object?> get props => [
        dominant,
        vibrant,
        lightVibrant,
        darkVibrant,
        muted,
        lightMuted,
        darkMuted,
        light,
        dark,
      ];
}
