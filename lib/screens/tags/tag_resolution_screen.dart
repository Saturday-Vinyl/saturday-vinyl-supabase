import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/tag_provider.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/library/album_card.dart';

/// Screen that resolves a tag EPC to its associated album.
///
/// If the tag is linked to an album, redirects to the album detail screen.
/// If the tag is not linked, shows a list of library albums to link it to.
class TagResolutionScreen extends ConsumerStatefulWidget {
  final String epc;

  const TagResolutionScreen({super.key, required this.epc});

  @override
  ConsumerState<TagResolutionScreen> createState() =>
      _TagResolutionScreenState();
}

class _TagResolutionScreenState extends ConsumerState<TagResolutionScreen> {
  bool _isAssociating = false;
  bool _hasRedirected = false;

  @override
  Widget build(BuildContext context) {
    final libraryAlbumAsync = ref.watch(libraryAlbumByEpcProvider(widget.epc));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saturday Tag'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _navigateAway(),
        ),
      ),
      body: SafeArea(
        child: libraryAlbumAsync.when(
          data: (libraryAlbum) {
            if (libraryAlbum != null) {
              if (!_hasRedirected) {
                _hasRedirected = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    context
                        .go('${RoutePaths.library}/album/${libraryAlbum.id}');
                  }
                });
              }
              return const LoadingIndicator.medium(
                message: 'Opening album...',
              );
            }
            return _buildNotLinkedState(context);
          },
          loading: () => const LoadingIndicator.medium(
            message: 'Looking up tag...',
          ),
          error: (error, stack) => ErrorDisplay.fullScreen(
            message: 'Failed to look up tag',
            onRetry: () =>
                ref.invalidate(libraryAlbumByEpcProvider(widget.epc)),
          ),
        ),
      ),
    );
  }

  Widget _buildNotLinkedState(BuildContext context) {
    final albumsAsync = ref.watch(allLibraryAlbumsProvider);

    return Column(
      children: [
        // Header
        Padding(
          padding: Spacing.pagePadding,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: SaturdayColors.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.nfc,
                  size: 40,
                  color: SaturdayColors.secondary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Tag Not Linked',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'This tag isn\'t linked to an album yet. '
                'Choose an album from your library to link it.',
                style: TextStyle(color: SaturdayColors.secondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),

        // Album list
        Expanded(
          child: albumsAsync.when(
            data: (albums) {
              if (albums.isEmpty) {
                return Center(
                  child: Padding(
                    padding: Spacing.pagePadding,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No albums in your library yet.',
                          style: TextStyle(color: SaturdayColors.secondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => context.go(RoutePaths.library),
                          child: const Text('Go to Library'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final libraryAlbum = albums[index];
                  return AlbumListTile(
                    libraryAlbum: libraryAlbum,
                    onTap: _isAssociating
                        ? null
                        : () => _associateAndNavigate(libraryAlbum.id),
                  );
                },
              );
            },
            loading: () => const LoadingIndicator.medium(
              message: 'Loading albums...',
            ),
            error: (error, stack) => ErrorDisplay.fullScreen(
              message: 'Failed to load albums',
              onRetry: () => ref.invalidate(allLibraryAlbumsProvider),
            ),
          ),
        ),

        // Loading overlay when associating
        if (_isAssociating)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LoadingIndicator(
              message: 'Linking tag...',
              size: LoadingIndicatorSize.small,
            ),
          ),
      ],
    );
  }

  Future<void> _associateAndNavigate(String libraryAlbumId) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to link tags')),
        );
      }
      return;
    }

    setState(() => _isAssociating = true);

    try {
      final tagRepo = ref.read(tagRepositoryProvider);
      await tagRepo.associateTag(widget.epc, libraryAlbumId, userId);

      // Invalidate tag providers so they reflect the new association
      ref.invalidate(libraryAlbumByEpcProvider(widget.epc));
      ref.invalidate(tagsForAlbumProvider(libraryAlbumId));

      if (mounted) {
        context.go('${RoutePaths.library}/album/$libraryAlbumId');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAssociating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to link tag: $e')),
        );
      }
    }
  }

  void _navigateAway() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.nowPlaying);
    }
  }
}
