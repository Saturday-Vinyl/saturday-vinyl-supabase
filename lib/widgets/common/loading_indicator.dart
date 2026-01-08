import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/config/styles.dart';

/// A branded loading indicator for the Saturday app.
///
/// Provides consistent loading states across the app with optional
/// message text and different size variants.
class LoadingIndicator extends StatelessWidget {
  /// Creates a loading indicator.
  const LoadingIndicator({
    super.key,
    this.message,
    this.size = LoadingIndicatorSize.medium,
    this.color,
  });

  /// Optional message to display below the spinner.
  final String? message;

  /// Size variant of the indicator.
  final LoadingIndicatorSize size;

  /// Custom color for the spinner. Defaults to primary dark.
  final Color? color;

  /// Creates a small inline loading indicator.
  const LoadingIndicator.small({
    super.key,
    this.color,
  })  : message = null,
        size = LoadingIndicatorSize.small;

  /// Creates a medium loading indicator with optional message.
  const LoadingIndicator.medium({
    super.key,
    this.message,
    this.color,
  }) : size = LoadingIndicatorSize.medium;

  /// Creates a large full-screen loading indicator.
  const LoadingIndicator.large({
    super.key,
    this.message,
    this.color,
  }) : size = LoadingIndicatorSize.large;

  double get _indicatorSize {
    switch (size) {
      case LoadingIndicatorSize.small:
        return 16;
      case LoadingIndicatorSize.medium:
        return 32;
      case LoadingIndicatorSize.large:
        return 48;
    }
  }

  double get _strokeWidth {
    switch (size) {
      case LoadingIndicatorSize.small:
        return 2;
      case LoadingIndicatorSize.medium:
        return 3;
      case LoadingIndicatorSize.large:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: _indicatorSize,
      height: _indicatorSize,
      child: CircularProgressIndicator(
        strokeWidth: _strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? SaturdayColors.primaryDark,
        ),
      ),
    );

    if (message == null) {
      return Center(child: indicator);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: Spacing.lg),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Size variants for [LoadingIndicator].
enum LoadingIndicatorSize {
  /// Small inline indicator (16px).
  small,

  /// Medium indicator (32px) - default.
  medium,

  /// Large full-screen indicator (48px).
  large,
}

/// A full-screen loading overlay.
///
/// Use this when you need to block user interaction during
/// an async operation.
class LoadingOverlay extends StatelessWidget {
  /// Creates a full-screen loading overlay.
  const LoadingOverlay({
    super.key,
    this.message,
    this.backgroundColor,
  });

  /// Optional message to display.
  final String? message;

  /// Background color of the overlay. Defaults to semi-transparent light.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? SaturdayColors.light.withValues(alpha: 0.9),
      child: LoadingIndicator.large(message: message),
    );
  }
}

/// A widget that shows a loading shimmer effect.
///
/// Use this as a placeholder for content that is loading.
class ShimmerPlaceholder extends StatefulWidget {
  /// Creates a shimmer placeholder.
  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  /// Width of the placeholder.
  final double width;

  /// Height of the placeholder.
  final double height;

  /// Border radius of the placeholder.
  final BorderRadius? borderRadius;

  /// Creates a circular shimmer placeholder.
  factory ShimmerPlaceholder.circular({
    Key? key,
    required double size,
  }) {
    return ShimmerPlaceholder(
      key: key,
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(size / 2),
    );
  }

  /// Creates a text line shimmer placeholder.
  factory ShimmerPlaceholder.text({
    Key? key,
    double width = 120,
    double height = 14,
  }) {
    return ShimmerPlaceholder(
      key: key,
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(4),
    );
  }

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? AppRadius.smallRadius,
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [
                SaturdayColors.secondary.withValues(alpha: 0.2),
                SaturdayColors.secondary.withValues(alpha: 0.4),
                SaturdayColors.secondary.withValues(alpha: 0.2),
              ],
            ),
          ),
        );
      },
    );
  }
}
