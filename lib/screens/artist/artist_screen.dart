import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';
import 'package:saturday_consumer_app/providers/artist_provider.dart';
import 'package:saturday_consumer_app/services/discogs_service.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/foundation/saturday_skeleton.dart';

/// Landing page for a Discogs artist.
///
/// Shows the artist's profile, albums in the user's library credited to
/// them, and the rest of their discography on Discogs as a path to add
/// new records. Routed by Discogs artist ID so two artists with the
/// same name resolve to distinct pages.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.discogsArtistId});

  final int discogsArtistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SaturdayColorTokens.of(context);
    final artistAsync = ref.watch(discogsArtistProvider(discogsArtistId));
    final libraryAlbumsAsync =
        ref.watch(libraryAlbumsByArtistProvider(discogsArtistId));
    final releasesState =
        ref.watch(discogsArtistReleasesProvider(discogsArtistId));

    return Scaffold(
      backgroundColor: colors.paper,
      appBar: const SaturdayAppBar(title: 'Artist'),
      body: SafeArea(
        child: artistAsync.when(
          loading: () => const Center(
            child: SaturdaySkeleton.rect(width: 200, height: 24),
          ),
          error: (e, _) => _Error(message: e.toString(), colors: colors),
          data: (artist) {
            if (artist == null) {
              return _Error(message: 'Artist not found', colors: colors);
            }
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
              children: [
                _Header(
                  artist: artist,
                  libraryCount:
                      libraryAlbumsAsync.maybeWhen(data: (a) => a.length, orElse: () => 0),
                  colors: colors,
                ),
                if (artist.profile != null && artist.profile!.isNotEmpty)
                  _Profile(profile: artist.profile!, colors: colors),
                _LibrarySection(
                  async: libraryAlbumsAsync,
                  colors: colors,
                  onTapAlbum: (album) =>
                      context.push('/library/album/${album.id}'),
                ),
                _DiscogsSection(
                  state: releasesState,
                  libraryAlbumsAsync: libraryAlbumsAsync,
                  colors: colors,
                  onAdd: (release) => _addRelease(context, ref, release),
                  onLoadMore: () => ref
                      .read(discogsArtistReleasesProvider(discogsArtistId)
                          .notifier)
                      .loadMore(),
                  onRetry: () => ref
                      .read(discogsArtistReleasesProvider(discogsArtistId)
                          .notifier)
                      .retry(),
                ),
                const SizedBox(height: Spacing.xxl),
              ],
            );
          },
        ),
      ),
    );
  }

  void _addRelease(
    BuildContext context,
    WidgetRef ref,
    DiscogsArtistRelease release,
  ) {
    // Reuse the existing add-album flow. A DiscogsSearchResult is the
    // shape the confirm screen expects; we synthesize one from the
    // discography row (which carries a release ID).
    ref.read(addAlbumProvider.notifier).selectFromSearchResult(
          DiscogsSearchResult(
            id: release.id,
            title: release.title,
            coverImageUrl: release.thumbUrl,
            year: release.year?.toString(),
          ),
        );
    context.push('/library/add/confirm');
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.artist,
    required this.libraryCount,
    required this.colors,
  });

  final DiscogsArtist artist;
  final int libraryCount;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: Spacing.pagePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArtistImage(url: artist.imageUrl, colors: colors),
          const SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: colors.ink,
                      ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  libraryCount == 1
                      ? '1 album in your archive'
                      : '$libraryCount albums in your archive',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.inkSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistImage extends StatelessWidget {
  const _ArtistImage({required this.url, required this.colors});

  final String? url;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: colors.paperElevated,
        border: Border.all(color: colors.borderQuiet),
        borderRadius: AppRadius.mediumRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _placeholder(),
              errorWidget: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Icon(Icons.person_outline, size: 40, color: colors.inkTertiary),
    );
  }
}

class _Profile extends StatefulWidget {
  const _Profile({required this.profile, required this.colors});

  final String profile;
  final SaturdayColorTokens colors;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: widget.colors.inkSecondary,
          height: 1.5,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.profile,
            maxLines: _expanded ? null : 5,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: style,
          ),
          const SizedBox(height: Spacing.xs),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Show more',
              style: style?.copyWith(
                color: widget.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.colors});

  final String title;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.ink,
            ),
      ),
    );
  }
}

class _LibrarySection extends StatelessWidget {
  const _LibrarySection({
    required this.async,
    required this.colors,
    required this.onTapAlbum,
  });

  final AsyncValue<List<LibraryAlbum>> async;
  final SaturdayColorTokens colors;
  final void Function(LibraryAlbum) onTapAlbum;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'In your archive', colors: colors),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: SaturdaySkeleton.rect(height: 48, width: double.infinity),
          ),
        ],
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (albums) {
        if (albums.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'In your archive', colors: colors),
            ...albums.map(
              (la) => _AlbumRow(
                title: la.album?.title ?? 'Unknown',
                subtitle: la.album?.year?.toString(),
                coverUrl: la.album?.coverImageUrl,
                colors: colors,
                onTap: () => onTapAlbum(la),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiscogsSection extends StatelessWidget {
  const _DiscogsSection({
    required this.state,
    required this.libraryAlbumsAsync,
    required this.colors,
    required this.onAdd,
    required this.onLoadMore,
    required this.onRetry,
  });

  final ArtistReleasesState state;
  final AsyncValue<List<LibraryAlbum>> libraryAlbumsAsync;
  final SaturdayColorTokens colors;
  final void Function(DiscogsArtistRelease) onAdd;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingInitial) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'More on Discogs', colors: colors),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: SaturdaySkeleton.rect(height: 48, width: double.infinity),
          ),
        ],
      );
    }

    if (state.releases.isEmpty && state.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'More on Discogs', colors: colors),
          _LoadMoreError(
            message: state.error!,
            onRetry: onRetry,
            colors: colors,
          ),
        ],
      );
    }

    final ownedReleaseIds = libraryAlbumsAsync.maybeWhen(
      data: (albums) =>
          albums.map((la) => la.album?.discogsId).whereType<int>().toSet(),
      orElse: () => <int>{},
    );

    final filtered = state.releases
        .where((r) => !ownedReleaseIds.contains(r.id))
        .toList();

    if (filtered.isEmpty && !state.hasMore) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'More on Discogs', colors: colors),
        ...filtered.map(
          (r) => _AlbumRow(
            title: r.title,
            subtitle: r.year?.toString(),
            coverUrl: r.thumbUrl,
            colors: colors,
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onAdd(r),
              tooltip: 'Add to Archive',
            ),
            onTap: () => onAdd(r),
          ),
        ),
        if (state.hasMore)
          _LoadMoreRow(
            isLoading: state.isLoadingMore,
            error: state.error,
            onTap: onLoadMore,
            colors: colors,
          ),
      ],
    );
  }
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({
    required this.isLoading,
    required this.error,
    required this.onTap,
    required this.colors,
  });

  final bool isLoading;
  final String? error;
  final VoidCallback onTap;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Text(
              error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.inkSecondary,
                  ),
            ),
            const SizedBox(height: Spacing.xs),
          ],
          InkWell(
            onTap: isLoading ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderQuiet),
                borderRadius: AppRadius.smallRadius,
              ),
              alignment: Alignment.center,
              child: isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.ink,
                      ),
                    )
                  : Text(
                      error != null ? 'Try again' : 'Load more',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({
    required this.message,
    required this.onRetry,
    required this.colors,
  });

  final String message;
  final VoidCallback onRetry;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.inkSecondary,
                ),
          ),
          const SizedBox(height: Spacing.xs),
          InkWell(
            onTap: onRetry,
            child: Text(
              'Try again',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.colors,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? coverUrl;
  final SaturdayColorTokens colors;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.paperElevated,
                border: Border.all(color: colors.borderQuiet),
                borderRadius: AppRadius.smallRadius,
              ),
              clipBehavior: Clip.antiAlias,
              child: coverUrl != null && coverUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Icon(
                        Icons.album_outlined,
                        color: colors.inkTertiary,
                      ),
                    )
                  : Icon(Icons.album_outlined, color: colors.inkTertiary),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.ink,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.inkSecondary,
                          ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.colors});

  final String message;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.inkSecondary,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
