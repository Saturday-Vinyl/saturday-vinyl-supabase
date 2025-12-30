import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A placeholder widget for animated illustrations.
///
/// This widget displays an animated placeholder until Lottie animations
/// are available. Once you have your .json animation files, replace
/// the placeholder with:
///
/// ```dart
/// Lottie.asset(
///   'assets/animations/your_animation.json',
///   repeat: true,
///   width: size,
///   height: size,
/// )
/// ```
class AnimatedIllustration extends StatefulWidget {
  const AnimatedIllustration({
    super.key,
    required this.type,
    this.size = 200,
  });

  /// The type of illustration to display.
  final IllustrationType type;

  /// The size of the illustration (width and height).
  final double size;

  @override
  State<AnimatedIllustration> createState() => _AnimatedIllustrationState();
}

class _AnimatedIllustrationState extends State<AnimatedIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    switch (widget.type) {
      case IllustrationType.welcomeVinyl:
        return _buildVinylPlaceholder();
      case IllustrationType.libraryCreated:
        return _buildSuccessPlaceholder();
      case IllustrationType.addAlbumIntro:
        return _buildAddAlbumPlaceholder();
    }
  }

  /// Spinning vinyl record placeholder using RotationTransition.
  Widget _buildVinylPlaceholder() {
    // RotationTransition is compositor-friendly and doesn't rebuild widgets
    return RotationTransition(
      turns: _controller,
      child: _VinylRecord(size: widget.size),
    );
  }

  /// Success checkmark with pulse effect.
  Widget _buildSuccessPlaceholder() {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const _PulseCurve(),
        ),
      ),
      child: _SuccessCheckmark(size: widget.size),
    );
  }

  /// Add album with floating effect.
  Widget _buildAddAlbumPlaceholder() {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.02),
        end: const Offset(0, -0.02),
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: const _FloatCurve(),
        ),
      ),
      child: _AlbumStack(size: widget.size),
    );
  }
}

/// Custom curve that creates a smooth pulse (goes up then down).
class _PulseCurve extends Curve {
  const _PulseCurve();

  @override
  double transform(double t) {
    // Creates a smooth sine wave that pulses
    return math.sin(t * 2 * math.pi);
  }
}

/// Custom curve for smooth floating up/down.
class _FloatCurve extends Curve {
  const _FloatCurve();

  @override
  double transform(double t) {
    return math.sin(t * 2 * math.pi);
  }
}

/// Static vinyl record widget (no animation logic here).
class _VinylRecord extends StatelessWidget {
  const _VinylRecord({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            SaturdayColors.primaryDark,
            SaturdayColors.primaryDark.withValues(alpha: 0.8),
            SaturdayColors.primaryDark,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: SaturdayColors.primaryDark.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Grooves
          ...List.generate(5, (index) {
            final radius = 0.3 + (index * 0.12);
            return Container(
              width: size * radius,
              height: size * radius,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            );
          }),
          // Center label
          Container(
            width: size * 0.25,
            height: size * 0.25,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SaturdayColors.light,
              border: Border.all(
                color: SaturdayColors.secondary,
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.music_note,
                size: size * 0.1,
                color: SaturdayColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Static success checkmark widget.
class _SuccessCheckmark extends StatelessWidget {
  const _SuccessCheckmark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SaturdayColors.success.withValues(alpha: 0.15),
      ),
      child: Center(
        child: Container(
          width: size * 0.6,
          height: size * 0.6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SaturdayColors.success,
            boxShadow: [
              BoxShadow(
                color: SaturdayColors.success.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.check_rounded,
            size: size * 0.35,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Static album stack widget.
class _AlbumStack extends StatelessWidget {
  const _AlbumStack({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Album stack
        ...List.generate(3, (index) {
          final offsetX = (2 - index) * 8.0;
          final offsetY = (2 - index) * 8.0;
          final opacity = 0.3 + (index * 0.3);
          return Transform.translate(
            offset: Offset(offsetX, offsetY),
            child: Container(
              width: size * 0.65,
              height: size * 0.65,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: SaturdayColors.primaryDark.withValues(alpha: opacity),
                boxShadow: index == 2
                    ? [
                        BoxShadow(
                          color:
                              SaturdayColors.primaryDark.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: index == 2
                  ? Center(
                      child: Icon(
                        Icons.album,
                        size: size * 0.3,
                        color: SaturdayColors.light,
                      ),
                    )
                  : null,
            ),
          );
        }),
        // Plus badge
        Positioned(
          right: size * 0.1,
          bottom: size * 0.1,
          child: Container(
            width: size * 0.25,
            height: size * 0.25,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SaturdayColors.success,
              boxShadow: [
                BoxShadow(
                  color: SaturdayColors.success.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.add,
              size: size * 0.15,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Types of animated illustrations available.
enum IllustrationType {
  /// Spinning vinyl record for welcome screen.
  welcomeVinyl,

  /// Success checkmark for library created confirmation.
  libraryCreated,

  /// Album stack with plus for add album intro.
  addAlbumIntro,
}
