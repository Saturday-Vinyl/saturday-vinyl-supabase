import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album.dart';

/// Displays album metadata for the Now Playing screen.
///
/// Shows album title (using Bevan font), artist name,
/// and optional year and label information.
class NowPlayingInfo extends StatelessWidget {
  const NowPlayingInfo({
    super.key,
    required this.album,
  });

  /// The album to display info for.
  final Album album;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Album title (Bevan font)
        Text(
          album.title,
          style: textTheme.headlineSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Spacing.xs),

        // Artist name
        Text(
          album.artist,
          style: textTheme.titleMedium?.copyWith(
            color: SaturdayColors.secondary,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        // Year and label (optional)
        if (album.year != null || album.label != null) ...[
          const SizedBox(height: Spacing.xs),
          _buildSubtitle(context),
        ],
      ],
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    final parts = <String>[];
    if (album.year != null) {
      parts.add(album.year.toString());
    }
    if (album.label != null && album.label!.isNotEmpty) {
      parts.add(album.label!);
    }

    return Text(
      parts.join(' \u2022 '), // Bullet separator
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: SaturdayColors.secondary,
          ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
