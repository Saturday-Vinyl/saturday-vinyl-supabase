import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/config/styles.dart';

/// A reusable error display widget with retry functionality.
///
/// Provides consistent error states across the app with different
/// variants for full-screen, inline, and snackbar displays.
class ErrorDisplay extends StatelessWidget {
  /// Creates an error display widget.
  const ErrorDisplay({
    super.key,
    required this.message,
    this.title,
    this.onRetry,
    this.retryLabel = 'Try Again',
    this.icon,
    this.variant = ErrorDisplayVariant.fullScreen,
  });

  /// The error message to display.
  final String message;

  /// Optional title for the error.
  final String? title;

  /// Callback when retry button is pressed. If null, no retry button shown.
  final VoidCallback? onRetry;

  /// Label for the retry button.
  final String retryLabel;

  /// Custom icon to display. Defaults to error_outline.
  final IconData? icon;

  /// The display variant.
  final ErrorDisplayVariant variant;

  /// Creates a full-screen error display.
  const ErrorDisplay.fullScreen({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
    this.retryLabel = 'Try Again',
    this.icon,
  }) : variant = ErrorDisplayVariant.fullScreen;

  /// Creates an inline error display (for use within cards/sections).
  const ErrorDisplay.inline({
    super.key,
    required this.message,
    this.title,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon,
  }) : variant = ErrorDisplayVariant.inline;

  /// Creates a compact error banner.
  const ErrorDisplay.banner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  })  : title = null,
        icon = null,
        variant = ErrorDisplayVariant.banner;

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case ErrorDisplayVariant.fullScreen:
        return _buildFullScreen(context);
      case ErrorDisplayVariant.inline:
        return _buildInline(context);
      case ErrorDisplayVariant.banner:
        return _buildBanner(context);
    }
  }

  Widget _buildFullScreen(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: SaturdayColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? Icons.error_outline,
                size: AppIconSizes.hero,
                color: SaturdayColors.error,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.sm),
            ],
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: Spacing.xl),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInline(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: SaturdayColors.error.withValues(alpha: 0.1),
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(
          color: SaturdayColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon ?? Icons.error_outline,
            size: AppIconSizes.lg,
            color: SaturdayColors.error,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: SaturdayColors.error,
                        ),
                  ),
                  const SizedBox(height: Spacing.xs),
                ],
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.primaryDark,
                      ),
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: Spacing.sm),
            TextButton(
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      color: SaturdayColors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: AppIconSizes.md,
            color: SaturdayColors.error,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.primaryDark,
                  ),
            ),
          ),
          if (onRetry != null) ...[
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(retryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Display variants for [ErrorDisplay].
enum ErrorDisplayVariant {
  /// Full-screen centered error with large icon.
  fullScreen,

  /// Inline error for use within cards or sections.
  inline,

  /// Compact banner error.
  banner,
}

/// Helper to show error snackbars with consistent styling.
class ErrorSnackBar {
  ErrorSnackBar._();

  /// Shows an error snackbar.
  static void show(
    BuildContext context, {
    required String message,
    VoidCallback? onRetry,
    String retryLabel = 'Retry',
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: SaturdayColors.white,
              size: AppIconSizes.md,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: SaturdayColors.error,
        duration: duration,
        action: onRetry != null
            ? SnackBarAction(
                label: retryLabel,
                textColor: SaturdayColors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }
}

/// Helper to show success snackbars with consistent styling.
class SuccessSnackBar {
  SuccessSnackBar._();

  /// Shows a success snackbar.
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: SaturdayColors.white,
              size: AppIconSizes.md,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: SaturdayColors.success,
        duration: duration,
        action: onAction != null && actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: SaturdayColors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}

/// Helper to show info snackbars with consistent styling.
class InfoSnackBar {
  InfoSnackBar._();

  /// Shows an info snackbar.
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.info_outline,
              color: SaturdayColors.white,
              size: AppIconSizes.md,
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: SaturdayColors.info,
        duration: duration,
        action: onAction != null && actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: SaturdayColors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}
