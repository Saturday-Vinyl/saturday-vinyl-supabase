import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/config/styles.dart';

/// A reusable empty state widget with optional CTA.
///
/// Use this to display friendly messages when content is empty,
/// guiding users on what to do next.
class EmptyState extends StatelessWidget {
  /// Creates an empty state widget.
  const EmptyState({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.iconWidget,
    this.onAction,
    this.actionLabel,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
  }) : assert(
          icon == null || iconWidget == null,
          'Cannot provide both icon and iconWidget',
        );

  /// The main message explaining the empty state.
  final String message;

  /// Optional title above the message.
  final String? title;

  /// Icon to display. Mutually exclusive with [iconWidget].
  final IconData? icon;

  /// Custom widget to display instead of icon (e.g., Lottie animation).
  final Widget? iconWidget;

  /// Callback for primary action button.
  final VoidCallback? onAction;

  /// Label for primary action button.
  final String? actionLabel;

  /// Label for secondary action button.
  final String? secondaryActionLabel;

  /// Callback for secondary action button.
  final VoidCallback? onSecondaryAction;

  /// Whether to use compact layout (less padding/spacing).
  final bool compact;

  /// Creates an empty state for empty library.
  factory EmptyState.library({
    Key? key,
    VoidCallback? onAddAlbum,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.album_outlined,
      title: 'No albums yet',
      message: 'Start building your vinyl collection by adding your first album.',
      actionLabel: 'Add Album',
      onAction: onAddAlbum,
    );
  }

  /// Creates an empty state for no search results.
  factory EmptyState.noSearchResults({
    Key? key,
    String? query,
    VoidCallback? onClearSearch,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.search_off,
      title: 'No results found',
      message: query != null
          ? 'No albums match "$query". Try a different search.'
          : 'No albums match your search. Try different keywords.',
      actionLabel: onClearSearch != null ? 'Clear Search' : null,
      onAction: onClearSearch,
    );
  }

  /// Creates an empty state for no devices.
  factory EmptyState.noDevices({
    Key? key,
    VoidCallback? onAddDevice,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.devices_outlined,
      title: 'No devices',
      message: 'Connect your Saturday Hub or Crate to get started.',
      actionLabel: 'Add Device',
      onAction: onAddDevice,
    );
  }

  /// Creates an empty state for nothing playing.
  factory EmptyState.nowPlaying({
    Key? key,
    VoidCallback? onSelectAlbum,
    VoidCallback? onScanBarcode,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.play_circle_outline,
      title: 'Nothing playing',
      message: 'Select an album from your library or scan a barcode to start listening.',
      actionLabel: 'Choose Album',
      onAction: onSelectAlbum,
      secondaryActionLabel: 'Scan Barcode',
      onSecondaryAction: onScanBarcode,
    );
  }

  /// Creates an empty state for no listening history.
  factory EmptyState.noHistory({
    Key? key,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.history,
      title: 'No listening history',
      message: 'Albums you play will appear here.',
    );
  }

  /// Creates an empty state for filtered results.
  factory EmptyState.noFilterResults({
    Key? key,
    VoidCallback? onClearFilters,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.filter_alt_off,
      title: 'No matching albums',
      message: 'Try adjusting your filters to see more results.',
      actionLabel: 'Clear Filters',
      onAction: onClearFilters,
    );
  }

  /// Creates an empty state for no tags associated.
  factory EmptyState.noTags({
    Key? key,
    VoidCallback? onAssociateTag,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.qr_code_2,
      title: 'No tag associated',
      message: 'Link a Saturday tag to automatically detect when this album is playing.',
      actionLabel: 'Scan Tag',
      onAction: onAssociateTag,
      compact: true,
    );
  }

  /// Creates an empty state for no recommendations.
  factory EmptyState.noRecommendations({
    Key? key,
  }) {
    return EmptyState(
      key: key,
      icon: Icons.recommend,
      message: 'Add more albums to your library to get personalized recommendations.',
      compact: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = compact ? Spacing.md : Spacing.xl;
    final iconSize = compact ? AppIconSizes.xl : AppIconSizes.feature;
    final iconContainerSize = compact ? 56.0 : 80.0;

    return Center(
      child: Padding(
        padding: compact
            ? const EdgeInsets.all(Spacing.lg)
            : Spacing.pagePadding * 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon or custom widget
            if (iconWidget != null)
              iconWidget!
            else if (icon != null)
              Container(
                width: iconContainerSize,
                height: iconContainerSize,
                decoration: BoxDecoration(
                  color: SaturdayColors.secondary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: SaturdayColors.secondary,
                ),
              ),

            if (icon != null || iconWidget != null)
              SizedBox(height: spacing),

            // Title
            if (title != null) ...[
              Text(
                title!,
                style: compact
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.sm),
            ],

            // Message
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),

            // Actions
            if (onAction != null && actionLabel != null) ...[
              SizedBox(height: spacing),
              if (compact)
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                )
              else
                ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
            ],

            // Secondary action
            if (onSecondaryAction != null && secondaryActionLabel != null) ...[
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A horizontal empty state for inline displays.
class EmptyStateInline extends StatelessWidget {
  /// Creates an inline empty state.
  const EmptyStateInline({
    super.key,
    required this.message,
    this.icon,
    this.onAction,
    this.actionLabel,
  });

  /// The message to display.
  final String message;

  /// Optional icon.
  final IconData? icon;

  /// Callback for action button.
  final VoidCallback? onAction;

  /// Label for action button.
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: SaturdayColors.secondary.withValues(alpha: 0.1),
        borderRadius: AppRadius.mediumRadius,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: AppIconSizes.lg,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(width: Spacing.md),
          ],
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(width: Spacing.sm),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
