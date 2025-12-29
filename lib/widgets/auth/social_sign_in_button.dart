import 'dart:io';

import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// Type of social sign-in provider.
enum SocialSignInProvider {
  apple,
  google,
}

/// A styled button for social sign-in (Apple, Google).
///
/// Follows platform-specific design guidelines:
/// - Apple: Black background with Apple logo
/// - Google: White background with Google logo
class SocialSignInButton extends StatelessWidget {
  final SocialSignInProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;

  const SocialSignInButton({
    super.key,
    required this.provider,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return switch (provider) {
      SocialSignInProvider.apple => _AppleSignInButton(
          onPressed: onPressed,
          isLoading: isLoading,
        ),
      SocialSignInProvider.google => _GoogleSignInButton(
          onPressed: onPressed,
          isLoading: isLoading,
        ),
    };
  }

  /// Returns whether this provider is available on the current platform.
  static bool isAvailable(SocialSignInProvider provider) {
    return switch (provider) {
      SocialSignInProvider.apple => Platform.isIOS || Platform.isMacOS,
      SocialSignInProvider.google => true,
    };
  }
}

class _AppleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const _AppleSignInButton({
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Apple logo (using SF Symbols-style icon)
                  const Icon(
                    Icons.apple,
                    size: 24,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Apple',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const _GoogleSignInButton({
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: SaturdayColors.primaryDark,
          side: const BorderSide(
            color: SaturdayColors.secondary,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SaturdayColors.primaryDark,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google "G" logo
                  _GoogleLogo(),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: SaturdayColors.primaryDark,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Google's colorful "G" logo.
class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Google logo colors
    const blue = Color(0xFF4285F4);
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final innerRadius = radius * 0.55;

    // Draw the colored arcs
    // Blue (right side)
    paint.color = blue;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -0.3,
      1.2,
      true,
      paint,
    );

    // Green (bottom right)
    paint.color = green;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.9,
      0.9,
      true,
      paint,
    );

    // Yellow (bottom left)
    paint.color = yellow;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      1.8,
      0.9,
      true,
      paint,
    );

    // Red (top)
    paint.color = red;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.7,
      1.0,
      true,
      paint,
    );

    // White inner circle to create the "G" shape
    paint.color = Colors.white;
    canvas.drawCircle(center, innerRadius, paint);

    // Blue horizontal bar (the "G" crossbar)
    paint.color = blue;
    final barRect = Rect.fromLTRB(
      center.dx - radius * 0.1,
      center.dy - radius * 0.15,
      center.dx + radius,
      center.dy + radius * 0.15,
    );
    canvas.drawRect(barRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
