import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A section header and content container for search results.
class SearchSection extends StatelessWidget {
  const SearchSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.resultCount,
    this.onSeeMore,
    this.maxItems,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final int? resultCount;
  final VoidCallback? onSeeMore;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    final displayChildren = maxItems != null && children.length > maxItems!
        ? children.take(maxItems!).toList()
        : children;

    final showSeeMore =
        onSeeMore != null && maxItems != null && children.length > maxItems!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: AppIconSizes.md,
                  color: SaturdayColors.secondary,
                ),
                const SizedBox(width: Spacing.sm),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (resultCount != null) ...[
                const SizedBox(width: Spacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: SaturdayColors.secondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    resultCount.toString(),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Results
        ...displayChildren,

        // See more button
        if (showSeeMore)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: TextButton(
              onPressed: onSeeMore,
              child: Text(
                'See all ${children.length} results',
              ),
            ),
          ),
      ],
    );
  }
}
