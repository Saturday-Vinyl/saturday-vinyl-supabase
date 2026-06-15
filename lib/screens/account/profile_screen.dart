import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album_analytics.dart';
import 'package:saturday_consumer_app/providers/album_analytics_provider.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';

/// Profile screen with album analytics for the signed-in user.
///
/// Reachable from the profile card on the Account tab. Shows totals,
/// most-played albums/artists/genres, an albums-by-decade heatmap, and a
/// 30-day play activity strip - all powered by a single
/// `get_user_album_analytics` RPC.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentSupabaseUserProvider);
    final analyticsAsync = ref.watch(albumAnalyticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Profile'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(albumAnalyticsProvider),
          child: ListView(
            padding: Spacing.pagePadding,
            children: [
              _ProfileHeader(user: user),
              Spacing.sectionGap,
              Text(
                'Your archive by the numbers',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'A look at how you listen and what fills your shelves.',
                style: TextStyle(
                  color: SaturdayColors.secondary,
                  fontSize: 14,
                ),
              ),
              Spacing.sectionGap,
              analyticsAsync.when(
                data: (data) {
                  if (data == null) {
                    return const _SignInPrompt();
                  }
                  if (!data.hasAnyPlays && data.totals.totalAlbums == 0) {
                    return const _EmptyAnalytics();
                  }
                  return _AnalyticsContent(analytics: data);
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => _AnalyticsError(
                  error: error,
                  onRetry: () => ref.invalidate(albumAnalyticsProvider),
                ),
              ),
              Spacing.sectionGap,
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final dynamic user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final name = user?.userMetadata?['full_name'] as String? ??
        user?.email as String? ??
        'You';
    final email = user?.email as String? ?? '';

    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: AppDecorations.avatar,
            child: const Icon(
              Icons.person,
              size: 32,
              color: SaturdayColors.white,
            ),
          ),
          Spacing.horizontalGapLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleLarge),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(
                      color: SaturdayColors.secondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  final AlbumAnalytics analytics;
  const _AnalyticsContent({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TotalsGrid(totals: analytics.totals),
        Spacing.sectionGap,
        _SectionHeader(
          title: 'Most-played albums',
          subtitle: analytics.topAlbums.isEmpty
              ? 'Drop a record on a Hub to start tracking'
              : null,
        ),
        Spacing.itemGap,
        if (analytics.topAlbums.isEmpty)
          const _EmptySectionCard(
            icon: Icons.album_outlined,
            text: 'No plays yet.',
          )
        else
          _TopAlbumsList(albums: analytics.topAlbums),
        Spacing.sectionGap,
        _SectionHeader(title: 'Top artists'),
        Spacing.itemGap,
        if (analytics.topArtists.isEmpty)
          const _EmptySectionCard(
            icon: Icons.person_outline,
            text: 'No artists ranked yet.',
          )
        else
          _RankedList(
            entries: [
              for (final a in analytics.topArtists)
                _RankedEntry(label: a.artist, count: a.playCount),
            ],
            countLabel: (n) => '$n play${n == 1 ? '' : 's'}',
          ),
        Spacing.sectionGap,
        _SectionHeader(title: 'Favorite genres'),
        Spacing.itemGap,
        if (analytics.topGenres.isEmpty)
          const _EmptySectionCard(
            icon: Icons.music_note_outlined,
            text: 'No genres ranked yet.',
          )
        else
          _GenreChips(genres: analytics.topGenres),
        Spacing.sectionGap,
        _SectionHeader(title: 'Albums by decade'),
        Spacing.itemGap,
        if (analytics.decades.isEmpty)
          const _EmptySectionCard(
            icon: Icons.calendar_today_outlined,
            text: 'Add albums with release years to see your decades.',
          )
        else
          _DecadeHeatmap(decades: analytics.decades),
        Spacing.sectionGap,
        _SectionHeader(title: 'Last 30 days'),
        Spacing.itemGap,
        _ActivityStrip(daily: analytics.dailyPlays),
      ],
    );
  }
}

class _TotalsGrid extends StatelessWidget {
  final AlbumAnalyticsTotals totals;
  const _TotalsGrid({required this.totals});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _TotalTile(
        icon: Icons.play_circle_outline,
        value: _format(totals.totalPlays),
        label: 'Plays',
      ),
      _TotalTile(
        icon: Icons.access_time,
        value: _formatHours(totals.totalSeconds),
        label: 'Listened',
      ),
      _TotalTile(
        icon: Icons.album_outlined,
        value: _format(totals.totalAlbums),
        label: 'Albums',
      ),
      _TotalTile(
        icon: Icons.person_outline,
        value: _format(totals.totalArtists),
        label: 'Artists',
      ),
      _TotalTile(
        icon: Icons.favorite_outline,
        value: _format(totals.totalFavorites),
        label: 'Favorites',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = Spacing.md;
        final columns = constraints.maxWidth > 520 ? 5 : 3;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final t in tiles)
              SizedBox(width: tileWidth, child: t),
          ],
        );
      },
    );
  }

  static String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  static String _formatHours(int seconds) {
    if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      return '${minutes}m';
    }
    final hours = seconds / 3600;
    if (hours >= 100) return '${hours.round()}h';
    return '${hours.toStringAsFixed(1)}h';
  }
}

class _TotalTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _TotalTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: SaturdayColors.primaryDark, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            label,
            style: TextStyle(
              color: SaturdayColors.secondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: SaturdayColors.primaryDark,
                fontWeight: FontWeight.w600,
              ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: TextStyle(
              color: SaturdayColors.secondary,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptySectionCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptySectionCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Row(
        children: [
          Icon(icon, color: SaturdayColors.secondary),
          Spacing.horizontalGapMd,
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: SaturdayColors.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopAlbumsList extends StatelessWidget {
  final List<TopAlbum> albums;
  const _TopAlbumsList({required this.albums});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < albums.length; i++) ...[
            _TopAlbumRow(rank: i + 1, album: albums[i]),
            if (i < albums.length - 1)
              Divider(
                height: 1,
                indent: 88,
                color: SaturdayColors.secondary.withValues(alpha: 0.2),
              ),
          ],
        ],
      ),
    );
  }
}

class _TopAlbumRow extends StatelessWidget {
  final int rank;
  final TopAlbum album;
  const _TopAlbumRow({required this.rank, required this.album});

  @override
  Widget build(BuildContext context) {
    final libraryAlbumId = album.libraryAlbumId;
    return InkWell(
      onTap: libraryAlbumId == null
          ? null
          : () => context.pushNamed(
                RouteNames.albumDetails,
                pathParameters: {'id': libraryAlbumId},
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: TextStyle(
                  color: SaturdayColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: AppRadius.smallRadius,
              child: SizedBox(
                width: 48,
                height: 48,
                child: album.coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: album.coverImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => _coverFallback(),
                        errorWidget: (_, __, ___) => _coverFallback(),
                      )
                    : _coverFallback(),
              ),
            ),
            Spacing.horizontalGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: SaturdayColors.secondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Spacing.horizontalGapSm,
            Text(
              '${album.playCount}×',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Icon(
        Icons.album_outlined,
        color: SaturdayColors.secondary,
      ),
    );
  }
}

class _RankedEntry {
  final String label;
  final int count;
  const _RankedEntry({required this.label, required this.count});
}

class _RankedList extends StatelessWidget {
  final List<_RankedEntry> entries;
  final String Function(int count) countLabel;

  const _RankedList({required this.entries, required this.countLabel});

  @override
  Widget build(BuildContext context) {
    final maxCount = entries.fold<int>(0, (m, e) => e.count > m ? e.count : m);

    return Container(
      decoration: AppDecorations.card(context),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _RankedRow(
              entry: entries[i],
              maxCount: maxCount,
              countLabel: countLabel,
            ),
            if (i < entries.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  final _RankedEntry entry;
  final int maxCount;
  final String Function(int) countLabel;

  const _RankedRow({
    required this.entry,
    required this.maxCount,
    required this.countLabel,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : entry.count / maxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              countLabel(entry.count),
              style: TextStyle(
                color: SaturdayColors.secondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: SaturdayColors.secondary.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              SaturdayColors.primaryDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _GenreChips extends StatelessWidget {
  final List<TopGenre> genres;
  const _GenreChips({required this.genres});

  @override
  Widget build(BuildContext context) {
    final maxCount = genres.fold<int>(0, (m, g) => g.playCount > m ? g.playCount : m);

    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final g in genres)
            _GenreChip(
              label: g.genre,
              count: g.playCount,
              weight: maxCount == 0 ? 0 : g.playCount / maxCount,
            ),
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String label;
  final int count;
  final double weight;

  const _GenreChip({
    required this.label,
    required this.count,
    required this.weight,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(
      SaturdayColors.secondary.withValues(alpha: 0.18),
      SaturdayColors.primaryDark,
      weight,
    )!;
    final isLight = weight < 0.5;
    final fg = isLight ? SaturdayColors.primaryDark : SaturdayColors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.smallRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DecadeHeatmap extends StatelessWidget {
  final List<DecadeBucket> decades;
  const _DecadeHeatmap({required this.decades});

  @override
  Widget build(BuildContext context) {
    final maxCount =
        decades.fold<int>(0, (m, d) => d.albumCount > m ? d.albumCount : m);

    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in decades) ...[
                  Expanded(
                    child: _DecadeBar(
                      label: d.label,
                      count: d.albumCount,
                      fraction: maxCount == 0 ? 0 : d.albumCount / maxCount,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DecadeBar extends StatelessWidget {
  final String label;
  final int count;
  final double fraction;

  const _DecadeBar({
    required this.label,
    required this.count,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              color: SaturdayColors.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final barHeight = (c.maxHeight * fraction).clamp(4.0, c.maxHeight);
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        SaturdayColors.secondary.withValues(alpha: 0.4),
                        SaturdayColors.primaryDark,
                        fraction.clamp(0.0, 1.0),
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ActivityStrip extends StatelessWidget {
  final List<DailyPlayCount> daily;
  const _ActivityStrip({required this.daily});

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return const _EmptySectionCard(
        icon: Icons.show_chart,
        text: 'No play activity yet.',
      );
    }

    final maxCount =
        daily.fold<int>(0, (m, d) => d.playCount > m ? d.playCount : m);
    final totalRecent = daily.fold<int>(0, (s, d) => s + d.playCount);

    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$totalRecent play${totalRecent == 1 ? '' : 's'} in the last ${daily.length} days',
            style: TextStyle(
              color: SaturdayColors.secondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in daily)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final fraction =
                              maxCount == 0 ? 0.0 : d.playCount / maxCount;
                          final h = (c.maxHeight * fraction)
                              .clamp(d.playCount > 0 ? 4.0 : 2.0, c.maxHeight);
                          return Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: h,
                              decoration: BoxDecoration(
                                color: d.playCount == 0
                                    ? SaturdayColors.secondary
                                        .withValues(alpha: 0.2)
                                    : Color.lerp(
                                        SaturdayColors.secondary
                                            .withValues(alpha: 0.5),
                                        SaturdayColors.primaryDark,
                                        fraction.clamp(0.0, 1.0),
                                      ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        },
                      ),
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

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline,
            color: SaturdayColors.secondary,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to see your stats',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Your album analytics live in your account.',
            style: TextStyle(color: SaturdayColors.secondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyAnalytics extends StatelessWidget {
  const _EmptyAnalytics();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.bar_chart,
            color: SaturdayColors.secondary,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            'No analytics yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Add albums to your archive and play a few records to see them light up here.',
            style: TextStyle(color: SaturdayColors.secondary),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _AnalyticsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: SaturdayColors.error, size: 28),
          const SizedBox(height: 8),
          Text(
            'Couldn\'t load your analytics',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '$error',
            style: TextStyle(color: SaturdayColors.secondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ],
      ),
    );
  }
}
