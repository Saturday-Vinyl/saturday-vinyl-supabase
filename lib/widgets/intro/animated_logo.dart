import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Animated Saturday logo for the intro splash screen.
///
/// Displays the Lottie animation of the logo with letters wiping in,
/// followed by the swoosh, then fading out.
class AnimatedLogo extends StatefulWidget {
  const AnimatedLogo({
    super.key,
    this.width = 200,
    this.onAnimationComplete,
  });

  /// Width of the logo (height scales proportionally).
  final double width;

  /// Callback when the animation completes.
  final VoidCallback? onAnimationComplete;

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this);
    _controller.addStatusListener(_onAnimationStatus);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_hasCompleted) {
      _hasCompleted = true;
      // Use post-frame callback to ensure we're not in the middle of a build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onAnimationComplete?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  void _onLottieLoaded(LottieComposition composition) {
    if (!mounted) return;
    _controller.duration = composition.duration;
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      'assets/animations/saturday-logo-intro.json',
      controller: _controller,
      width: widget.width,
      onLoaded: _onLottieLoaded,
      repeat: false,
    );
  }
}
