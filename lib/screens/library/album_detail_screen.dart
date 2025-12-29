import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/tag_provider.dart';
import 'package:saturday_consumer_app/utils/epc_validator.dart';
import 'package:saturday_consumer_app/widgets/library/album_location_badge.dart';
import 'package:saturday_consumer_app/widgets/library/track_list.dart';

/// Screen showing detailed information about an album.
///
/// Displays album art, metadata, track listing, location, and actions.
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.libraryAlbumId,
  });

  /// The ID of the library album to display.
  final String libraryAlbumId;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  final _notesController = TextEditingController();
  bool _isEditingNotes = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryAlbumAsync =
        ref.watch(libraryAlbumByIdProvider(widget.libraryAlbumId));

    return Scaffold(
      body: libraryAlbumAsync.when(
        data: (libraryAlbum) {
          if (libraryAlbum == null) {
            return _buildNotFoundState(context);
          }
          return _buildContent(context, libraryAlbum);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildErrorState(context, error.toString()),
      ),
    );
  }

  Widget _buildContent(BuildContext context, LibraryAlbum libraryAlbum) {
    final album = libraryAlbum.album;
    final canEdit = ref.watch(canEditCurrentLibraryProvider);

    return CustomScrollView(
      slivers: [
        // Hero app bar with album art
        _buildSliverAppBar(context, libraryAlbum),

        // Content
        SliverToBoxAdapter(
          child: Padding(
            padding: Spacing.pagePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and artist
                _buildHeader(context, libraryAlbum),
                const SizedBox(height: Spacing.lg),

                // Metadata chips (year, label, genres)
                if (album != null) _buildMetadataChips(context, album),
                const SizedBox(height: Spacing.xl),

                // Action buttons
                _buildActionButtons(context, libraryAlbum),
                const SizedBox(height: Spacing.xl),

                // Location
                _buildLocationSection(context, libraryAlbum),
                const SizedBox(height: Spacing.xl),

                // Track listing
                if (album != null && album.tracks.isNotEmpty) ...[
                  _buildSectionHeader(context, 'Tracks'),
                  const SizedBox(height: Spacing.sm),
                  TrackList(tracks: album.tracks),
                  const SizedBox(height: Spacing.lg),
                  _buildTotalDuration(context, album.formattedTotalDuration),
                  const SizedBox(height: Spacing.xl),
                ],

                // Notes
                _buildNotesSection(context, libraryAlbum, canEdit),
                const SizedBox(height: Spacing.xl),

                // Tags
                _buildTagsSection(context, libraryAlbum),
                const SizedBox(height: Spacing.xxl),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliverAppBar(BuildContext context, LibraryAlbum libraryAlbum) {
    final album = libraryAlbum.album;
    final coverUrl = album?.coverImageUrl;

    return SliverAppBar(
      expandedHeight: MediaQuery.of(context).size.width,
      pinned: true,
      stretch: true,
      backgroundColor: SaturdayColors.light,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SaturdayColors.light.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back),
        ),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: SaturdayColors.light.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              libraryAlbum.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: libraryAlbum.isFavorite ? SaturdayColors.error : null,
            ),
          ),
          onPressed: () => _toggleFavorite(libraryAlbum),
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: SaturdayColors.light.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.more_vert),
          ),
          onPressed: () => _showOptionsMenu(context, libraryAlbum),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: coverUrl != null
            ? CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildArtPlaceholder(),
                errorWidget: (context, url, error) => _buildArtPlaceholder(),
              )
            : _buildArtPlaceholder(),
      ),
    );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: 120,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, LibraryAlbum libraryAlbum) {
    final album = libraryAlbum.album;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          album?.title ?? 'Unknown Album',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          album?.artist ?? 'Unknown Artist',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: SaturdayColors.secondary,
                fontWeight: FontWeight.normal,
              ),
        ),
      ],
    );
  }

  Widget _buildMetadataChips(BuildContext context, dynamic album) {
    final chips = <Widget>[];

    if (album.year != null) {
      chips.add(_buildChip(context, album.year.toString(), Icons.calendar_today));
    }

    if (album.label != null && album.label!.isNotEmpty) {
      chips.add(_buildChip(context, album.label!, Icons.business));
    }

    for (final genre in album.genres.take(3)) {
      chips.add(_buildChip(context, genre, Icons.music_note));
    }

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: chips,
    );
  }

  Widget _buildChip(BuildContext context, String label, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildActionButtons(BuildContext context, LibraryAlbum libraryAlbum) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _setAsNowPlaying(libraryAlbum),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Set as Now Playing'),
          ),
        ),
        const SizedBox(width: Spacing.md),
        OutlinedButton.icon(
          onPressed: () => _associateTag(libraryAlbum),
          icon: const Icon(Icons.nfc),
          label: const Text('Associate Tag'),
        ),
      ],
    );
  }

  Widget _buildLocationSection(BuildContext context, LibraryAlbum libraryAlbum) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Location'),
        const SizedBox(height: Spacing.sm),
        // TODO: Get actual location from album_location model
        AlbumLocationBadge(
          crateName: null, // Will be populated when location feature is implemented
          isCurrentlyDetected: false,
          onTap: () {
            // TODO: Show location history or crate selector
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }

  Widget _buildTotalDuration(BuildContext context, String duration) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Total Duration: ',
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

  Widget _buildNotesSection(
    BuildContext context,
    LibraryAlbum libraryAlbum,
    bool canEdit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader(context, 'Notes'),
            if (canEdit && !_isEditingNotes)
              TextButton(
                onPressed: () {
                  setState(() {
                    _isEditingNotes = true;
                    _notesController.text = libraryAlbum.notes ?? '';
                  });
                },
                child: Text(
                  libraryAlbum.notes?.isEmpty ?? true ? 'Add' : 'Edit',
                ),
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        if (_isEditingNotes)
          _buildNotesEditor(context, libraryAlbum)
        else if (libraryAlbum.notes?.isNotEmpty ?? false)
          Text(
            libraryAlbum.notes!,
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Text(
            'No notes yet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                  fontStyle: FontStyle.italic,
                ),
          ),
      ],
    );
  }

  Widget _buildNotesEditor(BuildContext context, LibraryAlbum libraryAlbum) {
    return Column(
      children: [
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Add notes about this album...',
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                setState(() => _isEditingNotes = false);
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(width: Spacing.sm),
            ElevatedButton(
              onPressed: () => _saveNotes(libraryAlbum),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTagsSection(BuildContext context, LibraryAlbum libraryAlbum) {
    final tagsAsync = ref.watch(tagsForAlbumProvider(libraryAlbum.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Associated Tags'),
        const SizedBox(height: Spacing.sm),
        tagsAsync.when(
          data: (tags) {
            if (tags.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No tags associated',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SaturdayColors.secondary,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _associateTag(libraryAlbum),
                    icon: const Icon(Icons.add),
                    label: const Text('Associate Tag'),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...tags.map((tag) => Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                          vertical: Spacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: SaturdayColors.success.withValues(alpha: 0.1),
                          borderRadius: AppRadius.smallRadius,
                          border: Border.all(
                            color: SaturdayColors.success.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.nfc,
                              size: 16,
                              color: SaturdayColors.success,
                            ),
                            const SizedBox(width: Spacing.sm),
                            Text(
                              EpcValidator.formatEpcForDisplay(tag.epcIdentifier),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  onPressed: () => _associateTag(libraryAlbum),
                  icon: const Icon(Icons.add),
                  label: const Text('Associate Another Tag'),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (error, _) => Text(
            'Failed to load tags',
            style: TextStyle(color: SaturdayColors.error),
          ),
        ),
      ],
    );
  }

  Widget _buildNotFoundState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.album_outlined,
            size: 80,
            color: SaturdayColors.secondary,
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Album not found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: Spacing.xl),
          ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: SaturdayColors.error,
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Failed to load album',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(color: SaturdayColors.secondary),
          ),
          const SizedBox(height: Spacing.xl),
          ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(LibraryAlbum libraryAlbum) async {
    // TODO: Implement favorite toggle via repository
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          libraryAlbum.isFavorite
              ? 'Removed from favorites'
              : 'Added to favorites',
        ),
      ),
    );
  }

  void _setAsNowPlaying(LibraryAlbum libraryAlbum) {
    ref.read(nowPlayingProvider.notifier).setNowPlaying(libraryAlbum);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Now playing: "${libraryAlbum.album?.title}"'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => context.go(RoutePaths.nowPlaying),
        ),
      ),
    );
  }

  void _associateTag(LibraryAlbum libraryAlbum) {
    context.push('/library/album/${libraryAlbum.id}/tag');
  }

  Future<void> _saveNotes(LibraryAlbum libraryAlbum) async {
    // TODO: Save notes via repository
    setState(() => _isEditingNotes = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notes saved')),
    );
  }

  void _showOptionsMenu(BuildContext context, LibraryAlbum libraryAlbum) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement share
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: SaturdayColors.error,
              ),
              title: Text(
                'Remove from Library',
                style: TextStyle(color: SaturdayColors.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmRemove(libraryAlbum);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(LibraryAlbum libraryAlbum) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Album?'),
        content: Text(
          'Are you sure you want to remove "${libraryAlbum.album?.title}" from your library?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Remove album via repository
              this.context.pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: SaturdayColors.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
