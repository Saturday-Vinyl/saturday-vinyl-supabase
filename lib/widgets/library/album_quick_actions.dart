import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';

/// Shows a bottom sheet with quick actions for an album.
///
/// Actions include:
/// - Set as Now Playing
/// - View Details
/// - Associate NFC Tag
void showAlbumQuickActions(
  BuildContext context,
  WidgetRef ref,
  LibraryAlbum libraryAlbum,
) {
  final album = libraryAlbum.album;

  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with album info
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              children: [
                // Album art thumbnail
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.mediumRadius,
                    boxShadow: AppShadows.card,
                    color: SaturdayColors.secondary.withValues(alpha: 0.2),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.mediumRadius,
                    child: album?.coverImageUrl != null
                        ? Image.network(
                            album!.coverImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album?.title ?? 'Unknown Album',
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        album?.artist ?? 'Unknown Artist',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Action: Set as Now Playing
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Set as Now Playing'),
            onTap: () {
              Navigator.pop(context);
              ref.read(nowPlayingProvider.notifier).setNowPlaying(libraryAlbum);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Now playing: "${album?.title}"'),
                  action: SnackBarAction(
                    label: 'View',
                    onPressed: () => context.go(RoutePaths.nowPlaying),
                  ),
                ),
              );
            },
          ),

          // Action: View Details
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('View Details'),
            onTap: () {
              Navigator.pop(context);
              context.push('/library/album/${libraryAlbum.id}');
            },
          ),

          // Action: Associate NFC Tag
          ListTile(
            leading: const Icon(Icons.nfc),
            title: const Text('Associate NFC Tag'),
            onTap: () {
              Navigator.pop(context);
              context.push('/library/album/${libraryAlbum.id}/tag');
            },
          ),

          const SizedBox(height: Spacing.md),
        ],
      ),
    ),
  );
}

Widget _buildPlaceholder() {
  return Container(
    color: SaturdayColors.secondary.withValues(alpha: 0.2),
    child: Center(
      child: Icon(
        Icons.album_outlined,
        size: 24,
        color: SaturdayColors.secondary,
      ),
    ),
  );
}
