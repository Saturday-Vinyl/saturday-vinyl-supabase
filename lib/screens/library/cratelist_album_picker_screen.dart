import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/widgets/common/empty_state.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';

/// Multi-select album picker for adding records to a cratelist.
///
/// Shows albums from the current library, excluding ones already in the
/// cratelist. The user toggles selections, then taps "Add" to append them
/// (in selection order) to the end of the cratelist.
///
/// In v1 the picker only shows the current library. Picking from multiple
/// libraries is a future enhancement; users can switch libraries via the
/// library switcher and pick again.
class CratelistAlbumPickerScreen extends ConsumerStatefulWidget {
  const CratelistAlbumPickerScreen({
    super.key,
    required this.cratelistId,
  });

  final String cratelistId;

  @override
  ConsumerState<CratelistAlbumPickerScreen> createState() =>
      _CratelistAlbumPickerScreenState();
}

class _CratelistAlbumPickerScreenState
    extends ConsumerState<CratelistAlbumPickerScreen> {
  /// Library album ids selected for addition, in tap order.
  final List<String> _selectedOrder = [];
  final Set<String> _selectedSet = {};
  bool _submitting = false;

  void _toggle(String libraryAlbumId) {
    setState(() {
      if (_selectedSet.contains(libraryAlbumId)) {
        _selectedSet.remove(libraryAlbumId);
        _selectedOrder.remove(libraryAlbumId);
      } else {
        _selectedSet.add(libraryAlbumId);
        _selectedOrder.add(libraryAlbumId);
      }
    });
  }

  Future<void> _add() async {
    if (_selectedOrder.isEmpty) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(cratelistRepositoryProvider).addItems(
            cratelistId: widget.cratelistId,
            libraryAlbumIds: List<String>.from(_selectedOrder),
            userId: userId,
          );
      ref.invalidate(cratelistItemsProvider(widget.cratelistId));
      ref.invalidate(cratelistPreviewsProvider);
      if (!mounted) return;
      Navigator.pop(context, _selectedOrder.length);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add albums: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(libraryAlbumsProvider);
    final cratelistItemsAsync =
        ref.watch(cratelistItemsProvider(widget.cratelistId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add albums'),
        actions: [
          TextButton(
            onPressed: (_submitting || _selectedOrder.isEmpty) ? null : _add,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _selectedOrder.isEmpty
                        ? 'Add'
                        : 'Add (${_selectedOrder.length})',
                  ),
          ),
        ],
      ),
      body: albumsAsync.when(
        loading: () =>
            const LoadingIndicator.medium(message: 'Loading library...'),
        error: (e, _) => ErrorDisplay.fullScreen(
          message: e.toString(),
          onRetry: () => ref.invalidate(libraryAlbumsProvider),
        ),
        data: (albums) {
          final excludedIds = (cratelistItemsAsync.valueOrNull ?? const [])
              .map((it) => it.libraryAlbumId)
              .toSet();
          final available =
              albums.where((a) => !excludedIds.contains(a.id)).toList();

          if (available.isEmpty) {
            return EmptyState(
              icon: Icons.library_music_outlined,
              title: albums.isEmpty ? 'No albums' : 'All caught up',
              message: albums.isEmpty
                  ? 'Add albums to your library before grouping them into a '
                      'cratelist.'
                  : 'Every album in this library is already in the cratelist.',
            );
          }

          return ListView.builder(
            itemCount: available.length,
            itemBuilder: (context, index) {
              final album = available[index];
              final selected = _selectedSet.contains(album.id);
              final position = selected
                  ? _selectedOrder.indexOf(album.id) + 1
                  : null;

              return _AlbumPickerTile(
                libraryAlbum: album,
                selected: selected,
                position: position,
                onTap: _submitting ? null : () => _toggle(album.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _AlbumPickerTile extends StatelessWidget {
  const _AlbumPickerTile({
    required this.libraryAlbum,
    required this.selected,
    required this.position,
    required this.onTap,
  });

  final LibraryAlbum libraryAlbum;
  final bool selected;
  final int? position;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final album = libraryAlbum.album;
    final coverUrl = album?.coverImageUrl;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: AppRadius.smallRadius,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
            const SizedBox(width: Spacing.sm),
            _SelectionIndicator(selected: selected, position: position),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Icon(
        Icons.album_outlined,
        size: AppIconSizes.md,
        color: SaturdayColors.secondary,
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected, required this.position});

  final bool selected;
  final int? position;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return Icon(
        Icons.radio_button_unchecked,
        color: SaturdayColors.secondary.withValues(alpha: 0.6),
      );
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '${position ?? ''}',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
