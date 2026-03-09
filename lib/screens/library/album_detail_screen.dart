import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album_colors.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/realtime_album_location_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
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

    // Trigger lazy backfill of colors if this album doesn't have them yet
    if (album != null && album.colors == null) {
      ref.watch(albumColorsBackfillProvider(album.id));
    }

    // Resolve palette colors for immersive styling
    final albumColors = album?.colors;
    final dominant = AlbumColors.parseHex(albumColors?.dominant);
    final vibrant = AlbumColors.parseHex(albumColors?.vibrant);
    final darkVibrant = AlbumColors.parseHex(albumColors?.darkVibrant);
    final darkMuted = AlbumColors.parseHex(albumColors?.darkMuted);
    final muted = AlbumColors.parseHex(albumColors?.muted);

    // Derived colors with fallbacks
    final gradientBase = darkVibrant ?? darkMuted ?? dominant;
    final appBarColor = gradientBase != null
        ? Color.lerp(gradientBase, SaturdayColors.light, 0.3)!
        : SaturdayColors.light;
    final accentColor = vibrant ?? dominant;
    final chipTint = muted ?? dominant;
    final artistColor = darkVibrant ?? muted ?? SaturdayColors.secondary;

    return CustomScrollView(
      slivers: [
        // Hero app bar with album art
        _buildSliverAppBar(context, libraryAlbum, appBarColor: appBarColor, accentColor: accentColor),

        // Content with full-page gradient background
        SliverToBoxAdapter(
          child: DecoratedBox(
            decoration: gradientBase != null
                ? BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.4, 1.0],
                      colors: [
                        gradientBase.withValues(alpha: 0.35),
                        gradientBase.withValues(alpha: 0.12),
                        SaturdayColors.light,
                      ],
                    ),
                  )
                : const BoxDecoration(),
            child: Padding(
              padding: Spacing.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Spacing.lg),

                  // Title and artist
                  _buildHeader(context, libraryAlbum, artistColor: artistColor),
                  const SizedBox(height: Spacing.lg),

                  // Metadata chips (year, label, genres)
                  if (album != null) _buildMetadataChips(context, album, chipTint: chipTint),
                  const SizedBox(height: Spacing.xl),

                  // Action buttons
                  _buildActionButtons(context, libraryAlbum, accentColor: accentColor),
                  const SizedBox(height: Spacing.xl),

                  // Divider
                  if (accentColor != null) _buildAccentDivider(accentColor),
                  const SizedBox(height: Spacing.xl),

                  // Location
                  _buildLocationSection(context, libraryAlbum),
                  const SizedBox(height: Spacing.xl),

                  // Track listing
                  if (album != null && album.tracks.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Tracks', accentColor: accentColor),
                    const SizedBox(height: Spacing.sm),
                    TrackList(tracks: album.tracks, accentColor: accentColor),
                    const SizedBox(height: Spacing.lg),
                    _buildTotalDuration(context, album.formattedTotalDuration),
                    const SizedBox(height: Spacing.xl),
                  ],

                  // Notes
                  _buildNotesSection(context, libraryAlbum, canEdit),
                  const SizedBox(height: Spacing.xl),

                  // Tags
                  _buildTagsSection(context, libraryAlbum),
                  const SizedBox(height: Spacing.xl),

                  // Debug: Color palette
                  if (albumColors != null) _buildColorPaletteDebug(context, albumColors),
                  const SizedBox(height: Spacing.xxl),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    LibraryAlbum libraryAlbum, {
    required Color appBarColor,
    Color? accentColor,
  }) {
    final album = libraryAlbum.album;
    final coverUrl = album?.coverImageUrl;
    final buttonBg = appBarColor.withValues(alpha: 0.9);
    final favoriteColor = accentColor ?? SaturdayColors.error;

    return SliverAppBar(
      expandedHeight: MediaQuery.of(context).size.width,
      pinned: true,
      stretch: true,
      backgroundColor: appBarColor,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: buttonBg,
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
              color: buttonBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              libraryAlbum.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: libraryAlbum.isFavorite ? favoriteColor : null,
            ),
          ),
          onPressed: () => _toggleFavorite(libraryAlbum),
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: buttonBg,
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

  Widget _buildHeader(BuildContext context, LibraryAlbum libraryAlbum, {Color? artistColor}) {
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
                color: artistColor ?? SaturdayColors.secondary,
                fontWeight: FontWeight.normal,
              ),
        ),
      ],
    );
  }

  Widget _buildMetadataChips(BuildContext context, dynamic album, {Color? chipTint}) {
    final chips = <Widget>[];

    if (album.year != null) {
      chips.add(_buildChip(context, album.year.toString(), Icons.calendar_today, tint: chipTint));
    }

    if (album.label != null && album.label!.isNotEmpty) {
      chips.add(_buildChip(context, album.label!, Icons.business, tint: chipTint));
    }

    for (final genre in album.genres.take(3)) {
      chips.add(_buildChip(context, genre, Icons.music_note, tint: chipTint));
    }

    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: chips,
    );
  }

  Widget _buildChip(BuildContext context, String label, IconData icon, {Color? tint}) {
    return Chip(
      avatar: Icon(icon, size: 16, color: tint),
      label: Text(label),
      backgroundColor: tint?.withValues(alpha: 0.1),
      side: tint != null ? BorderSide(color: tint.withValues(alpha: 0.2)) : null,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildActionButtons(BuildContext context, LibraryAlbum libraryAlbum, {Color? accentColor}) {
    final tagsAsync = ref.watch(tagsForAlbumProvider(libraryAlbum.id));
    final hasTag = tagsAsync.valueOrNull?.isNotEmpty ?? false;

    // Choose contrasting foreground for the accent button
    final buttonFg = accentColor != null
        ? (accentColor.computeLuminance() > 0.4 ? SaturdayColors.black : Colors.white)
        : null;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _setAsNowPlaying(libraryAlbum),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Now Playing'),
            style: accentColor != null
                ? ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: buttonFg,
                  )
                : null,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: hasTag
              ? Container(
                  padding: const EdgeInsets.symmetric(
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.nfc,
                        size: 18,
                        color: SaturdayColors.success,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Text(
                        'Tracked',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: SaturdayColors.success,
                            ),
                      ),
                    ],
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: () => _associateTag(libraryAlbum),
                  icon: const Icon(Icons.nfc),
                  label: const Text('Associate Tag'),
                ),
        ),
      ],
    );
  }

  Widget _buildLocationSection(BuildContext context, LibraryAlbum libraryAlbum) {
    final location = ref.watch(albumLocationProvider(libraryAlbum.id));

    final deviceAsync = location != null
        ? ref.watch(deviceByIdProvider(location.deviceId))
        : null;
    final deviceName = deviceAsync?.whenOrNull(
      data: (device) => device?.name,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Location'),
        const SizedBox(height: Spacing.sm),
        AlbumLocationBadge(
          crateName: deviceName,
          lastSeen: location?.detectedAt,
          isCurrentlyDetected: location?.isPresent ?? false,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {Color? accentColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: accentColor,
              ),
        ),
        if (accentColor != null) ...[
          const SizedBox(height: 4),
          Container(
            width: 32,
            height: 2,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAccentDivider(Color color) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.4),
            color.withValues(alpha: 0.05),
          ],
        ),
      ),
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
        _buildSectionHeader(context, 'Associated Tag'),
        const SizedBox(height: Spacing.sm),
        tagsAsync.when(
          data: (tags) {
            if (tags.isEmpty) {
              return Text(
                'No tag associated',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SaturdayColors.secondary,
                      fontStyle: FontStyle.italic,
                    ),
              );
            }
            final tag = tags.first;
            return Container(
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

  Widget _buildColorPaletteDebug(BuildContext context, AlbumColors colors) {
    final namedColors = <String, String?>{
      'dominant': colors.dominant,
      'vibrant': colors.vibrant,
      'lightVibrant': colors.lightVibrant,
      'darkVibrant': colors.darkVibrant,
      'muted': colors.muted,
      'lightMuted': colors.lightMuted,
      'darkMuted': colors.darkMuted,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Color Palette'),
        const SizedBox(height: Spacing.sm),

        // Named colors
        ...namedColors.entries.map((entry) {
          final color = AlbumColors.parseHex(entry.value);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color ?? Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: SaturdayColors.secondary.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  entry.key,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Text(
                  entry.value ?? '—',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: SaturdayColors.secondary,
                      ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: Spacing.md),

        // Light colors (LED-safe)
        Text(
          'Light (LED-safe): ${colors.light.length}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: colors.light.map((hex) {
            final color = AlbumColors.parseHex(hex);
            return Tooltip(
              message: hex,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: SaturdayColors.secondary.withValues(alpha: 0.3),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: Spacing.md),

        // Dark colors (UI only)
        Text(
          'Dark (UI only): ${colors.dark.length}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: Spacing.xs),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: colors.dark.map((hex) {
            final color = AlbumColors.parseHex(hex);
            return Tooltip(
              message: hex,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: SaturdayColors.secondary.withValues(alpha: 0.3),
                  ),
                ),
              ),
            );
          }).toList(),
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
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
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
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
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
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
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
            onPressed: () async {
              Navigator.pop(context);
              await _removeAlbum(libraryAlbum);
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

  Future<void> _removeAlbum(LibraryAlbum libraryAlbum) async {
    try {
      final albumRepo = ref.read(albumRepositoryProvider);
      await albumRepo.removeAlbumFromLibrary(libraryAlbum.id);

      // Invalidate the library albums provider to refresh the list
      ref.invalidate(libraryAlbumsProvider);
      ref.invalidate(allLibraryAlbumsProvider);
      ref.invalidate(libraryAlbumCountProvider);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '"${libraryAlbum.album?.title}" removed from library',
              ),
            ),
          );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Failed to remove album: $e'),
              backgroundColor: SaturdayColors.error,
            ),
          );
      }
    }
  }
}
