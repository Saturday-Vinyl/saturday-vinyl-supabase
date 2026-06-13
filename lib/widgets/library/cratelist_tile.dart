import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';
import 'package:saturday_consumer_app/widgets/library/cratelist_cover.dart';

/// A tile representing a single cratelist: 2x2 cover composite, name, and
/// item count. Used in the unified library grid (with [showTypeIndicator]
/// to surface a small badge that distinguishes cratelist tiles from album
/// tiles), and in the dedicated cratelists screen.
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
  /// is rendered alongside album tiles so they're distinguishable at a
  /// glance.
  final bool showTypeIndicator;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
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
                  top: SaturdaySpace.space2,
                  right: SaturdaySpace.space2,
                  child: _CratelistBadge(),
                ),
            ],
          ),
          const SizedBox(height: SaturdaySpace.space2),
          Text(
            cratelist.name,
            style: SaturdayType.body.copyWith(
              fontWeight: SaturdayType.medium,
              color: colors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _countLabel(preview.itemCount),
            style: SaturdayType.meta.copyWith(color: colors.inkSecondary),
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

/// "Create your first cratelist" tile. Visually matches CratelistTile so
/// the section reads consistently when empty.
class CreateCratelistTile extends StatelessWidget {
  const CreateCratelistTile({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: DottedBorderBox(
              child: Center(
                child: Icon(Icons.add, size: 32, color: colors.inkSecondary),
              ),
            ),
          ),
          const SizedBox(height: SaturdaySpace.space2),
          Text(
            'New cratelist',
            style: SaturdayType.body.copyWith(
              fontWeight: SaturdayType.medium,
              color: colors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Group albums to play',
            style: SaturdayType.meta.copyWith(color: colors.inkSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Small badge laid over a cratelist cover composite to signal that the
/// tile is a cratelist (not a single album) in the unified library grid.
class _CratelistBadge extends StatelessWidget {
  const _CratelistBadge();

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.ink.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.library_music, size: 14, color: colors.paper),
    );
  }
}

/// Bordered placeholder used by CreateCratelistTile.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderQuiet, width: 1),
        color: colors.paperElevated,
      ),
      child: child,
    );
  }
}
