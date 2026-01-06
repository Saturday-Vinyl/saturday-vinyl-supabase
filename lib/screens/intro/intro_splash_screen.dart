import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/providers/intro_splash_provider.dart';
import 'package:saturday_consumer_app/widgets/intro/animated_logo.dart';

/// Intro splash screen shown on first launch and after app updates.
///
/// Displays an animated Saturday logo and automatically navigates
/// to the main app after the animation completes.
class IntroSplashScreen extends ConsumerStatefulWidget {
  const IntroSplashScreen({super.key});

  @override
  ConsumerState<IntroSplashScreen> createState() => _IntroSplashScreenState();
}

class _IntroSplashScreenState extends ConsumerState<IntroSplashScreen> {
  bool _hasNavigated = false;

  Future<void> _onAnimationComplete() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    // Mark splash as shown and wait for state to update
    await ref.read(introSplashNotifierProvider.notifier).markSplashShown();

    // Navigate to main app
    if (mounted) {
      context.go(RoutePaths.nowPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaturdayColors.light,
      body: Center(
        child: AnimatedLogo(
          width: MediaQuery.of(context).size.width * 0.6,
          onAnimationComplete: _onAnimationComplete,
        ),
      ),
    );
  }
}
