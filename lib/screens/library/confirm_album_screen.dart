import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/widgets/library/track_list.dart';

/// Screen for confirming and adding an album to the library.
class ConfirmAlbumScreen extends ConsumerStatefulWidget {
  const ConfirmAlbumScreen({super.key});

  @override
  ConsumerState<ConfirmAlbumScreen> createState() => _ConfirmAlbumScreenState();
}

class _ConfirmAlbumScreenState extends ConsumerState<ConfirmAlbumScreen> {
  // Tracks whether we've ever rendered a selected album. The auto-pop
  // logic exists to bounce users who land here with nothing loaded; once
  // we've shown an album, a later transition to null is the user
  // back-navigating away — popping again would over-pop and skip the
  // referring screen.
  bool _hasEverHadAlbum = false;

  void _goBack() {
    // Pop BEFORE clearing selection. Clearing first would rebuild this
    // widget with album == null, scheduling a second auto-pop on the
    // next frame.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/library');
    }
    ref.read(addAlbumProvider.notifier).clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addAlbumProvider);
    final album = state.selectedAlbum;

    if (album != null) {
      _hasEverHadAlbum = true;
    } else if (!_hasEverHadAlbum) {
      // No album selected and we never had one — bounce out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/library');
        }
      });
      return const SizedBox.shrink();
    } else {
      // We had an album but it's been cleared — we're already on the way
      // out. Render nothing while the pop animates.
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Album'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: Column(
        children: [
          // Album details
          Expanded(
            child: SingleChildScrollView(
              padding: Spacing.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Album art and basic info
                  _buildHeader(context, album),
                  const SizedBox(height: Spacing.xl),

                  // Metadata
                  _buildMetadata(context, album),
                  const SizedBox(height: Spacing.xl),

                  // Track list
                  if (album.tracks.isNotEmpty) ...[
                    Text(
                      'Tracks',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Spacing.sm),
                    TrackList(tracks: album.tracks),
                    const SizedBox(height: Spacing.md),
                    _buildTotalDuration(context, album.formattedTotalDuration),
                  ],

                  const SizedBox(height: Spacing.xl),
                ],
              ),
            ),
          ),

          // Error message
          if (state.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.md),
              color: SaturdayColors.error.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: SaturdayColors.error),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: TextStyle(color: SaturdayColors.error),
                    ),
                  ),
                ],
              ),
            ),

          // Add button
          SafeArea(
            child: Padding(
              padding: Spacing.pagePadding,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: state.isAdding
                      ? null
                      : () => _addToLibrary(context, ref),
                  child: state.isAdding
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add to Archive'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Album album) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Album art
        ClipRRect(
          borderRadius: AppRadius.mediumRadius,
          child: SizedBox(
            width: 120,
            height: 120,
            child: album.coverImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: album.coverImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _buildArtPlaceholder(),
                    errorWidget: (context, url, error) => _buildArtPlaceholder(),
                  )
                : _buildArtPlaceholder(),
          ),
        ),
        const SizedBox(width: Spacing.lg),

        // Title and artist
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                album.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                album.artist,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: SaturdayColors.secondary,
                    ),
              ),
              if (album.year != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  album.year.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.secondary,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.album,
          size: 48,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }

  Widget _buildMetadata(BuildContext context, Album album) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (album.label != null && album.label!.isNotEmpty) ...[
          _buildMetadataRow(context, 'Label', album.label!),
          const SizedBox(height: Spacing.sm),
        ],
        if (album.genres.isNotEmpty) ...[
          _buildMetadataRow(context, 'Genre', album.genres.join(', ')),
          const SizedBox(height: Spacing.sm),
        ],
        if (album.styles.isNotEmpty) ...[
          _buildMetadataRow(context, 'Style', album.styles.join(', ')),
          const SizedBox(height: Spacing.sm),
        ],
        if (album.discogsId != null) ...[
          _buildMetadataRow(context, 'Discogs ID', album.discogsId.toString()),
        ],
      ],
    );
  }

  Widget _buildMetadataRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildTotalDuration(BuildContext context, String duration) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Total: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SaturdayColors.secondary,
              ),
        ),
        Text(
          duration,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Future<void> _addToLibrary(BuildContext context, WidgetRef ref) async {
    final success = await ref.read(addAlbumProvider.notifier).addToLibrary();

    if (!context.mounted) return;

    if (success) {
      final addedAlbum = ref.read(addAlbumProvider).addedAlbum;

      // Show success message
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Added "${addedAlbum?.album?.title}" to your archive'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                if (addedAlbum != null) {
                  context.go('/library/album/${addedAlbum.id}');
                }
              },
            ),
          ),
        );

      // Invalidate library albums to refresh the list
      ref.invalidate(libraryAlbumsProvider);
      ref.invalidate(allLibraryAlbumsProvider);

      // Reset state and go back to library
      ref.read(addAlbumProvider.notifier).reset();
      context.go('/library');
    }
  }
}
