import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// Empty state display for when nothing is currently playing.
///
/// Shows a friendly message and multiple call-to-action options
/// to guide users to select an album.
class NowPlayingEmptyState extends StatelessWidget {
  const NowPlayingEmptyState({
    super.key,
    this.onChooseAlbum,
    this.onScanBarcode,
    this.onPhotoOfCover,
  });

  /// Callback when the user wants to choose an album from the library.
  final VoidCallback? onChooseAlbum;

  /// Callback when the user wants to scan a barcode.
  final VoidCallback? onScanBarcode;

  /// Callback when the user wants to take a photo of the album cover.
  final VoidCallback? onPhotoOfCover;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: Spacing.pagePadding,
      decoration: AppDecorations.albumArt,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Album icon
            Icon(
              Icons.album_outlined,
              size: 80,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.lg),

            // Title
            Text(
              'No record playing',
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),

            // Description
            Text(
              'Place a record on your turntable to get started,\nor choose one using the options below.',
              style: textTheme.bodyMedium?.copyWith(
                color: SaturdayColors.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),

            // Primary CTA - Browse Library
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onChooseAlbum,
                icon: const Icon(Icons.library_music_outlined),
                label: const Text('Browse Library'),
              ),
            ),
            const SizedBox(height: Spacing.md),

            // Secondary CTAs Row
            Row(
              children: [
                // Scan Barcode
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onScanBarcode,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan'),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                // Photo of Cover
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPhotoOfCover,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Photo'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
