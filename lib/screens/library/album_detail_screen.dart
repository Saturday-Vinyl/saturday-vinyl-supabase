import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/models/album_colors.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/playback_queue_provider.dart';
import 'package:saturday_consumer_app/providers/realtime_album_location_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/tag_provider.dart';
import 'package:saturday_consumer_app/utils/epc_validator.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/foundation/saturday_skeleton.dart';
import 'package:saturday_consumer_app/widgets/library/tag_method_picker.dart';
import 'package:saturday_consumer_app/widgets/library/track_list.dart';

/// Detail view for a record in the collection.
///
/// Archive posture per the constitution: paper/ink only, no album-derived
/// color on the surface, no streaming-app primitives (favorites, queue, play
/// buttons, snackbars, confirm dialogs). The cover is the only color object
/// on the page; the record speaks for itself.
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.libraryAlbumId,
  });

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
    final colors = SaturdayColorTokens.of(context);

    return Scaffold(
      backgroundColor: colors.paper,
      appBar: SaturdayAppBar(
        title: 'Archive',
        actions: libraryAlbumAsync.maybeWhen(
          data: (libraryAlbum) => libraryAlbum != null
              ? [
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () => _showOptionsMenu(context, libraryAlbum),
                  ),
                ]
              : null,
          orElse: () => null,
        ),
      ),
      body: SafeArea(
        child: libraryAlbumAsync.when(
          data: (libraryAlbum) {
            if (libraryAlbum == null) return _NotFound(colors: colors);
            return _AlbumDetailBody(
              libraryAlbum: libraryAlbum,
              colors: colors,
              notesController: _notesController,
              isEditingNotes: _isEditingNotes,
              onStartEditing: (notes) => setState(() {
                _isEditingNotes = true;
                _notesController.text = notes ?? '';
              }),
              onCancelEditing: () => setState(() => _isEditingNotes = false),
              onSaveNotes: () => _saveNotes(libraryAlbum),
            );
          },
          loading: () => _LoadingPlaceholder(colors: colors),
          error: (error, _) => _ErrorView(
            colors: colors,
            message: error.toString(),
          ),
        ),
      ),
    );
  }

  Future<void> _saveNotes(LibraryAlbum libraryAlbum) async {
    // TODO: persist via repository when the witness repo lands.
    if (!mounted) return;
    setState(() => _isEditingNotes = false);
  }

  void _showOptionsMenu(BuildContext context, LibraryAlbum libraryAlbum) {
    final colors = SaturdayColorTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.paperElevated,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.ios_share, color: colors.ink),
              title: Text(
                'Share',
                style: SaturdayType.body.copyWith(color: colors.ink),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                // TODO: implement share
              },
            ),
            ListTile(
              leading: Icon(Icons.remove_circle_outline, color: colors.ink),
              title: Text(
                'Remove from collection',
                style: SaturdayType.body.copyWith(color: colors.ink),
              ),
              onTap: () {
                // Destructive proceeds without confirmation. Recovery is
                // re-adding the record. Inline undo at the collection list
                // is an open question.
                Navigator.pop(sheetContext);
                _removeAlbum(libraryAlbum);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeAlbum(LibraryAlbum libraryAlbum) async {
    try {
      final albumRepo = ref.read(albumRepositoryProvider);
      await albumRepo.removeAlbumFromLibrary(libraryAlbum.id);

      ref.invalidate(libraryAlbumsProvider);
      ref.invalidate(allLibraryAlbumsProvider);
      ref.invalidate(libraryAlbumCountProvider);

      if (mounted) context.pop();
    } catch (e) {
      debugPrint('[AlbumDetail] remove failed: $e');
    }
  }
}

// =============================================================================
// Body
// =============================================================================

class _AlbumDetailBody extends ConsumerWidget {
  const _AlbumDetailBody({
    required this.libraryAlbum,
    required this.colors,
    required this.notesController,
    required this.isEditingNotes,
    required this.onStartEditing,
    required this.onCancelEditing,
    required this.onSaveNotes,
  });

  final LibraryAlbum libraryAlbum;
  final SaturdayColorTokens colors;
  final TextEditingController notesController;
  final bool isEditingNotes;
  final void Function(String? currentNotes) onStartEditing;
  final VoidCallback onCancelEditing;
  final Future<void> Function() onSaveNotes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = libraryAlbum.album;
    final canEdit = ref.watch(canEditCurrentLibraryProvider);

    // Lazy backfill of palette colors (used by the debug section).
    if (album != null && album.colors == null) {
      ref.watch(albumColorsBackfillProvider(album.id));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space16,
      ),
      children: [
        _Cover(album: album, colors: colors),
        const SizedBox(height: SaturdaySpace.space8),
        _Header(album: album, colors: colors),
        const SizedBox(height: SaturdaySpace.space3),
        _MetaLine(album: album, colors: colors),
        const SizedBox(height: SaturdaySpace.space8),
        _SendToTheRoomAction(libraryAlbum: libraryAlbum, colors: colors),
        const SizedBox(height: SaturdaySpace.space8),
        _SectionEyebrow(label: 'Where', colors: colors),
        const SizedBox(height: SaturdaySpace.space3),
        _LocationLine(libraryAlbum: libraryAlbum, colors: colors),
        if (album != null && album.tracks.isNotEmpty) ...[
          const SizedBox(height: SaturdaySpace.space8),
          _SectionEyebrow(label: 'Sides', colors: colors),
          const SizedBox(height: SaturdaySpace.space3),
          TrackList(tracks: album.tracks),
          const SizedBox(height: SaturdaySpace.space3),
          _AlbumTotal(album: album, colors: colors),
        ],
        const SizedBox(height: SaturdaySpace.space8),
        _SectionEyebrow(label: 'Witness', colors: colors),
        const SizedBox(height: SaturdaySpace.space3),
        _WitnessSection(
          libraryAlbum: libraryAlbum,
          colors: colors,
          canEdit: canEdit,
          controller: notesController,
          isEditing: isEditingNotes,
          onStartEditing: onStartEditing,
          onCancel: onCancelEditing,
          onSave: onSaveNotes,
        ),
        const SizedBox(height: SaturdaySpace.space8),
        _SectionEyebrow(label: 'Tag', colors: colors),
        const SizedBox(height: SaturdaySpace.space3),
        _TagSection(libraryAlbum: libraryAlbum, colors: colors),
        if (kDebugMode && album?.colors != null) ...[
          const SizedBox(height: SaturdaySpace.space12),
          _SectionEyebrow(label: 'Palette (debug)', colors: colors),
          const SizedBox(height: SaturdaySpace.space3),
          _ColorPaletteDebug(palette: album!.colors!, colors: colors),
        ],
      ],
    );
  }
}

// =============================================================================
// Cover
// =============================================================================

class _Cover extends StatelessWidget {
  const _Cover({required this.album, required this.colors});

  final Album? album;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final coverUrl = album?.coverImageUrl;
    final maxSize = MediaQuery.of(context).size.width * 0.72;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxSize),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderQuiet),
                borderRadius: BorderRadius.circular(2),
                color: colors.paperElevated,
              ),
              child: coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          _CoverPlaceholder(colors: colors),
                      errorWidget: (context, url, error) =>
                          _CoverPlaceholder(colors: colors),
                    )
                  : _CoverPlaceholder(colors: colors),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.paperElevated,
      alignment: Alignment.center,
      child: Icon(
        Icons.album_outlined,
        size: 64,
        color: colors.inkTertiary,
      ),
    );
  }
}

// =============================================================================
// Header (title / artist)
// =============================================================================

class _Header extends StatelessWidget {
  const _Header({required this.album, required this.colors});

  final Album? album;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          album?.title ?? 'Untitled record',
          style: SaturdayType.titleArchive.copyWith(
            color: colors.ink,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: SaturdaySpace.space1),
        _ArtistLine(album: album, colors: colors),
      ],
    );
  }
}

/// Artist credit line. When the album has Discogs artist IDs, each name
/// renders as a tappable link to that artist's landing page; when it
/// doesn't (legacy or non-Discogs records), falls back to plain text.
class _ArtistLine extends StatelessWidget {
  const _ArtistLine({required this.album, required this.colors});

  final Album? album;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final style = SaturdayType.body.copyWith(
      color: colors.inkSecondary,
      fontSize: 16,
    );

    if (album == null) {
      return Text('Artist unknown', style: style);
    }

    final ids = album!.discogsArtistIds;
    final names = album!.discogsArtistNames;
    final hasLinks = ids.isNotEmpty && ids.length == names.length;

    if (!hasLinks) {
      return Text(album!.artist, style: style);
    }

    final children = <Widget>[];
    for (var i = 0; i < ids.length; i++) {
      if (i > 0) children.add(Text(', ', style: style));
      final id = ids[i];
      final name = names[i];
      children.add(
        InkWell(
          onTap: () => context.push('/artist/discogs/$id'),
          child: Text(
            name,
            style: style.copyWith(
              color: colors.ink,
              decoration: TextDecoration.underline,
              decorationColor: colors.borderStrong,
            ),
          ),
        ),
      );
    }
    return Wrap(children: children);
  }
}

// =============================================================================
// Meta line (year · label · genre)
// =============================================================================

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.album, required this.colors});

  final Album? album;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    if (album == null) return const SizedBox.shrink();

    final parts = <String>[
      if (album!.year != null) album!.year.toString(),
      if (album!.label != null && album!.label!.isNotEmpty) album!.label!,
      ...album!.genres.take(2),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join('  ·  '),
      style: SaturdayType.meta.copyWith(color: colors.inkTertiary),
    );
  }
}

// =============================================================================
// Send-to-the-room action
// =============================================================================

class _SendToTheRoomAction extends ConsumerWidget {
  const _SendToTheRoomAction({
    required this.libraryAlbum,
    required this.colors,
  });

  final LibraryAlbum libraryAlbum;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowPlaying = ref.watch(nowPlayingProvider);
    final queue = ref.watch(playbackQueueProvider).items;

    final isOnStand = nowPlaying.currentAlbum?.id == libraryAlbum.id;
    final queueIndex =
        queue.indexWhere((item) => item.libraryAlbumId == libraryAlbum.id);

    final String label;
    final VoidCallback? onTap;

    if (isOnStand) {
      final side = nowPlaying.currentSide;
      if (nowPlaying.isPlaying) {
        label = side.isEmpty ? 'On the stand.' : 'On the stand. Side $side.';
      } else {
        label = 'Waiting on the stand.';
      }
      onTap = () => context.go(RoutePaths.nowPlaying);
    } else if (queueIndex >= 0) {
      label = '${_ordinalUp(queueIndex)} in the room.';
      onTap = () => context.go(RoutePaths.nowPlaying);
    } else {
      label = 'Send to the room';
      onTap = () => _send(ref);
    }

    return _ArchiveButton(
      label: label,
      onTap: onTap,
      colors: colors,
      isPrimary: !isOnStand && queueIndex < 0,
    );
  }

  Future<void> _send(WidgetRef ref) async {
    // Sending a record to the room always places it on the stand, replacing
    // whatever is there. queueOnStand cancels any existing active session
    // (via queueSession -> _cancelExistingActive) before queueing the new
    // record, so the previous session — even one left lingering in `queued`
    // after a finished or stopped record — is terminated first.
    await ref.read(nowPlayingProvider.notifier).queueOnStand(libraryAlbum);
  }

  String _ordinalUp(int zeroIndexed) {
    switch (zeroIndexed) {
      case 0:
        return 'Next up';
      case 1:
        return 'Second up';
      case 2:
        return 'Third up';
      case 3:
        return 'Fourth up';
      case 4:
        return 'Fifth up';
      default:
        return 'Up later';
    }
  }
}

class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({
    required this.label,
    required this.onTap,
    required this.colors,
    required this.isPrimary,
  });

  final String label;
  final VoidCallback? onTap;
  final SaturdayColorTokens colors;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: isPrimary ? colors.ink : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(
            color: isPrimary ? colors.ink : colors.borderStrong,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SaturdaySpace.space4,
              vertical: SaturdaySpace.space3,
            ),
            child: Center(
              child: Text(
                label,
                style: SaturdayType.body.copyWith(
                  color: isPrimary ? colors.paper : colors.ink,
                  fontWeight: SaturdayType.medium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Section eyebrow
// =============================================================================

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.label, required this.colors});

  final String label;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: SaturdayType.eyebrow.copyWith(color: colors.inkSecondary),
    );
  }
}

// =============================================================================
// Location
// =============================================================================

class _LocationLine extends ConsumerWidget {
  const _LocationLine({required this.libraryAlbum, required this.colors});

  final LibraryAlbum libraryAlbum;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(albumLocationProvider(libraryAlbum.id));
    if (location == null) {
      return Text(
        "Not seen in any crate yet.",
        style: SaturdayType.body.copyWith(color: colors.inkSecondary),
      );
    }

    final deviceAsync = ref.watch(deviceByIdProvider(location.deviceId));
    final deviceName =
        deviceAsync.whenOrNull(data: (device) => device?.name) ??
            'an unknown crate';

    final primary = location.isPresent
        ? 'In $deviceName.'
        : 'Last seen in $deviceName.';

    final secondary = !location.isPresent
        ? _relativeTime(location.detectedAt)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          style: SaturdayType.body.copyWith(color: colors.ink),
        ),
        if (secondary != null) ...[
          const SizedBox(height: SaturdaySpace.space1),
          Text(
            secondary,
            style: SaturdayType.meta.copyWith(color: colors.inkTertiary),
          ),
        ],
      ],
    );
  }

  String _relativeTime(DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 1) return 'A moment ago.';
    if (delta.inMinutes < 60) return '${delta.inMinutes} minutes ago.';
    if (delta.inHours < 24) return '${delta.inHours} hours ago.';
    if (delta.inDays < 7) return '${delta.inDays} days ago.';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}.';
  }
}

// =============================================================================
// Album total duration
// =============================================================================

class _AlbumTotal extends StatelessWidget {
  const _AlbumTotal({required this.album, required this.colors});

  final Album album;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: SaturdaySpace.space2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Album total',
              style: SaturdayType.meta.copyWith(color: colors.inkTertiary),
            ),
          ),
          Text(
            album.formattedTotalDuration,
            style: SaturdayType.mono.copyWith(color: colors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Witness (replaces "notes")
// =============================================================================

class _WitnessSection extends StatelessWidget {
  const _WitnessSection({
    required this.libraryAlbum,
    required this.colors,
    required this.canEdit,
    required this.controller,
    required this.isEditing,
    required this.onStartEditing,
    required this.onCancel,
    required this.onSave,
  });

  final LibraryAlbum libraryAlbum;
  final SaturdayColorTokens colors;
  final bool canEdit;
  final TextEditingController controller;
  final bool isEditing;
  final void Function(String? currentNotes) onStartEditing;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    if (isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: controller,
            maxLines: 5,
            minLines: 3,
            style: SaturdayType.bodySerif.copyWith(color: colors.ink),
            decoration: InputDecoration(
              hintText: 'Note something true.',
              hintStyle:
                  SaturdayType.bodySerif.copyWith(color: colors.inkTertiary),
              filled: true,
              fillColor: colors.paperElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: colors.borderQuiet),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: colors.borderQuiet),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: colors.ink),
              ),
            ),
          ),
          const SizedBox(height: SaturdaySpace.space2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: Text(
                  'Cancel',
                  style: SaturdayType.body.copyWith(color: colors.inkSecondary),
                ),
              ),
              const SizedBox(width: SaturdaySpace.space2),
              TextButton(
                onPressed: () => onSave(),
                child: Text(
                  'Save',
                  style: SaturdayType.body.copyWith(
                    color: colors.ink,
                    fontWeight: SaturdayType.medium,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final notes = libraryAlbum.notes;
    final hasNotes = notes != null && notes.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasNotes)
          Text(
            notes,
            style: SaturdayType.bodySerif.copyWith(color: colors.ink),
          )
        else
          Text(
            'No witness yet.',
            style: SaturdayType.bodySerif.copyWith(color: colors.inkTertiary),
          ),
        if (canEdit) ...[
          const SizedBox(height: SaturdaySpace.space2),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => onStartEditing(notes),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SaturdaySpace.space1,
                ),
                child: Text(
                  hasNotes ? 'Edit' : 'Add a witness entry',
                  style: SaturdayType.bodySmall.copyWith(
                    color: colors.ink,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.borderStrong,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Tag
// =============================================================================

class _TagSection extends ConsumerWidget {
  const _TagSection({required this.libraryAlbum, required this.colors});

  final LibraryAlbum libraryAlbum;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsForAlbumProvider(libraryAlbum.id));

    return tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No tag yet.',
                style: SaturdayType.body.copyWith(color: colors.inkSecondary),
              ),
              const SizedBox(height: SaturdaySpace.space2),
              GestureDetector(
                onTap: () => showTagMethodPicker(context, ref, libraryAlbum.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: SaturdaySpace.space1,
                  ),
                  child: Text(
                    'Associate a tag',
                    style: SaturdayType.bodySmall.copyWith(
                      color: colors.ink,
                      decoration: TextDecoration.underline,
                      decorationColor: colors.borderStrong,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        final tag = tags.first;
        return Text(
          EpcValidator.formatEpcForDisplay(tag.epcIdentifier),
          style: SaturdayType.mono.copyWith(color: colors.ink),
        );
      },
      loading: () => SaturdaySkeleton.rect(
        width: 220,
        height: 16,
      ),
      error: (error, _) => Text(
        "Tag isn't loading.",
        style: SaturdayType.body.copyWith(color: colors.inkSecondary),
      ),
    );
  }
}

// =============================================================================
// Debug palette
// =============================================================================

class _ColorPaletteDebug extends StatelessWidget {
  const _ColorPaletteDebug({required this.palette, required this.colors});

  final AlbumColors palette;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final namedColors = <String, String?>{
      'dominant': palette.dominant,
      'vibrant': palette.vibrant,
      'lightVibrant': palette.lightVibrant,
      'darkVibrant': palette.darkVibrant,
      'muted': palette.muted,
      'lightMuted': palette.lightMuted,
      'darkMuted': palette.darkMuted,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in namedColors.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AlbumColors.parseHex(entry.value) ??
                        Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: colors.borderQuiet),
                  ),
                ),
                const SizedBox(width: SaturdaySpace.space3),
                Expanded(
                  child: Text(
                    entry.key,
                    style: SaturdayType.bodySmall.copyWith(color: colors.ink),
                  ),
                ),
                Text(
                  entry.value ?? '—',
                  style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Loading + states
// =============================================================================

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final coverSize = MediaQuery.of(context).size.width * 0.72;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space16,
      ),
      children: [
        Center(child: SaturdaySkeleton.square(size: coverSize)),
        const SizedBox(height: SaturdaySpace.space8),
        SaturdaySkeleton.rect(width: 240, height: 28),
        const SizedBox(height: SaturdaySpace.space3),
        SaturdaySkeleton.rect(width: 160, height: 16),
        const SizedBox(height: SaturdaySpace.space3),
        SaturdaySkeleton.rect(width: 200, height: 12),
        const SizedBox(height: SaturdaySpace.space8),
        SaturdaySkeleton.rect(width: double.infinity, height: 44),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SaturdaySpace.space8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "This record isn't in the collection.",
            style: SaturdayType.section.copyWith(color: colors.ink),
          ),
          const SizedBox(height: SaturdaySpace.space3),
          GestureDetector(
            onTap: () => context.pop(),
            child: Text(
              'Back',
              style: SaturdayType.body.copyWith(
                color: colors.ink,
                decoration: TextDecoration.underline,
                decorationColor: colors.borderStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.colors, required this.message});

  final SaturdayColorTokens colors;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SaturdaySpace.space8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Record details aren't loading.",
            style: SaturdayType.section.copyWith(color: colors.ink),
          ),
          const SizedBox(height: SaturdaySpace.space2),
          Text(
            message,
            style: SaturdayType.bodySmall.copyWith(color: colors.inkTertiary),
          ),
          const SizedBox(height: SaturdaySpace.space3),
          GestureDetector(
            onTap: () => context.pop(),
            child: Text(
              'Back',
              style: SaturdayType.body.copyWith(
                color: colors.ink,
                decoration: TextDecoration.underline,
                decorationColor: colors.borderStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
