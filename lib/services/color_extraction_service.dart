import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:saturday_consumer_app/models/album_colors.dart';

/// Extracts dominant colors from album cover art images.
///
/// Uses [PaletteGenerator] to sample colors and classifies them by
/// relative luminance into LED-safe (light) and UI-only (dark) groups.
class ColorExtractionService {
  /// Colors with relative luminance >= this value are considered "light"
  /// and suitable for LED display. Below this threshold, colors appear
  /// too dim on WS2812B-style RGB LEDs.
  static const double luminanceThreshold = 0.18;

  /// Maximum number of palette colors to extract.
  static const int maxPaletteColors = 16;

  /// Extract colors from a network image URL.
  ///
  /// Returns null on failure — album creation should not be blocked
  /// by color extraction errors.
  Future<AlbumColors?> extractFromUrl(String imageUrl) async {
    try {
      final imageProvider = CachedNetworkImageProvider(imageUrl);
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: maxPaletteColors,
        size: const Size(200, 200),
      );
      return _buildAlbumColors(paletteGenerator);
    } catch (e) {
      debugPrint('Color extraction failed: $e');
      return null;
    }
  }

  AlbumColors _buildAlbumColors(PaletteGenerator palette) {
    final dominant = palette.dominantColor?.color;
    final vibrant = palette.vibrantColor?.color;
    final lightVibrant = palette.lightVibrantColor?.color;
    final darkVibrant = palette.darkVibrantColor?.color;
    final muted = palette.mutedColor?.color;
    final lightMuted = palette.lightMutedColor?.color;
    final darkMuted = palette.darkMutedColor?.color;

    // Classify all palette colors by luminance
    final light = <String>[];
    final dark = <String>[];
    final seen = <String>{};

    for (final paletteColor in palette.paletteColors) {
      final hex = _colorToHex(paletteColor.color);
      if (seen.contains(hex)) continue;
      seen.add(hex);

      if (_isLightColor(paletteColor.color)) {
        light.add(hex);
      } else {
        dark.add(hex);
      }
    }

    // Include named swatch colors in appropriate lists if not already present
    final allNamed = [
      dominant, vibrant, lightVibrant, darkVibrant,
      muted, lightMuted, darkMuted,
    ].whereType<Color>();

    for (final color in allNamed) {
      final hex = _colorToHex(color);
      if (seen.contains(hex)) continue;
      seen.add(hex);

      if (_isLightColor(color)) {
        light.add(hex);
      } else {
        dark.add(hex);
      }
    }

    return AlbumColors(
      dominant: dominant != null ? _colorToHex(dominant) : null,
      vibrant: vibrant != null ? _colorToHex(vibrant) : null,
      lightVibrant: lightVibrant != null ? _colorToHex(lightVibrant) : null,
      darkVibrant: darkVibrant != null ? _colorToHex(darkVibrant) : null,
      muted: muted != null ? _colorToHex(muted) : null,
      lightMuted: lightMuted != null ? _colorToHex(lightMuted) : null,
      darkMuted: darkMuted != null ? _colorToHex(darkMuted) : null,
      light: light,
      dark: dark,
    );
  }

  bool _isLightColor(Color color) {
    return color.computeLuminance() >= luminanceThreshold;
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }
}
