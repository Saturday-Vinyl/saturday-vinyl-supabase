import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';
import 'package:saturday_consumer_app/widgets/library/cratelist_cover.dart';

/// A tile representing a single cratelist: 2x2 cover composite, name, and
/// item count. Used in the unified library grid (with [showTypeIndicator]
/// to surface a small "stack" badge that distinguishes cratelist tiles from
/// album tiles), and in the dedicated cratelists screen.
class CratelistTile extends StatelessWidget {
  const CratelistTile({
    super.key,
    required this.preview,
    this.onTap,
    this.showTypeIndicator = false,
  });

  final CratelistPreview preview;
  final VoidCallback? onTap;

  /// Adds a small stack-of-records badge on the cover. Use when this tile
  /// is rendered alongside album tiles so users can tell them apart at a
  /// glance.
  final bool showTypeIndicator;

  @override
  Widget build(BuildContext context) {
    final cratelist = preview.cratelist;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              CratelistCover(coverUrls: preview.coverUrls),
              if (showTypeIndicator)
                const Positioned(
                  top: Spacing.sm,
                  right: Spacing.sm,
                  child: _CratelistBadge(),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            cratelist.name,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _countLabel(preview.itemCount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _countLabel(int count) {
    if (count == 0) return 'Empty';
    if (count == 1) return '1 album';
    return '$count albums';
  }
}

/// "Create your first cratelist" tile. Visually matches CratelistTile so the
/// horizontal section reads consistently when empty.
class CreateCratelistTile extends StatelessWidget {
  const CreateCratelistTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DottedBorderBox(
              child: Center(
                child: Icon(
                  Icons.add,
                  size: AppIconSizes.feature,
                  color: SaturdayColors.secondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'New cratelist',
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Group albums to play',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Small "stack of records" badge laid over a cratelist cover composite
/// to signal that the tile is a cratelist (not a single album) when
/// rendered in the unified library grid.
class _CratelistBadge extends StatelessWidget {
  const _CratelistBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.library_music,
        size: 14,
        color: Colors.white,
      ),
    );
  }
}

/// Simple bordered placeholder used by CreateCratelistTile.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.largeRadius,
        border: Border.all(
          color: SaturdayColors.secondary.withValues(alpha: 0.4),
          width: 1.5,
        ),
        color: SaturdayColors.secondary.withValues(alpha: 0.05),
      ),
      child: child,
    );
  }
}
