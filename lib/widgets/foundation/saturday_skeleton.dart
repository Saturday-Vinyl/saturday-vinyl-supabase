import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';

/// Held loading space, per the Saturday constitution.
///
/// Loading uses [SaturdaySkeleton] — paper-tone shapes that hold layout
/// dimensions while content is pending. Content replaces the skeleton via
/// the `arrive` motion gesture once ready.
///
/// The skeleton is intentionally **static**. No infinite pulse, no shimmer,
/// no animated brightness. The constitution forbids motion that demands a
/// response — a shimmer that loops until tapped is one. A held shape is the
/// opposite: stillness while the system waits.
///
/// Usage:
///
/// ```dart
/// // A 16-pixel block sized for a metadata line.
/// SaturdaySkeleton.rect(width: 120, height: 16)
///
/// // Three lines of body-sized text.
/// SaturdaySkeleton.text(lines: 3, fontSize: 14)
///
/// // Album art placeholder.
/// SaturdaySkeleton.square(size: 200)
///
/// // Avatar.
/// SaturdaySkeleton.circle(diameter: 48)
/// ```
class SaturdaySkeleton extends StatelessWidget {
  /// Rectangular skeleton with explicit width and height.
  const SaturdaySkeleton.rect({
    super.key,
    required this.width,
    required this.height,
    this.radius = 4,
  }) : shape = BoxShape.rectangle;

  /// Square skeleton, typically for album art.
  const SaturdaySkeleton.square({
    super.key,
    required double size,
    this.radius = 8,
  }) : width = size,
       height = size,
       shape = BoxShape.rectangle;

  /// Circular skeleton, for avatars and round affordances.
  const SaturdaySkeleton.circle({super.key, required double diameter})
    : width = diameter,
      height = diameter,
      shape = BoxShape.circle,
      radius = 0;

  final double width;
  final double height;
  final BoxShape shape;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.paperElevated,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(radius)
            : null,
        border: Border.all(color: colors.borderQuiet),
      ),
    );
  }

  /// Multiple skeleton lines sized for a text block.
  ///
  /// `lines` is the number of rows. `fontSize` drives the line height and
  /// inter-line gap so the placeholder occupies the same vertical space as
  /// the rendered text it stands in for. The last line is rendered short
  /// to mimic the ragged edge of real prose.
  static Widget text({
    Key? key,
    int lines = 3,
    double fontSize = 14,
    double lastLineFraction = 0.6,
  }) {
    return _SaturdaySkeletonText(
      key: key,
      lines: lines,
      fontSize: fontSize,
      lastLineFraction: lastLineFraction,
    );
  }
}

class _SaturdaySkeletonText extends StatelessWidget {
  const _SaturdaySkeletonText({
    super.key,
    required this.lines,
    required this.fontSize,
    required this.lastLineFraction,
  });

  final int lines;
  final double fontSize;
  final double lastLineFraction;

  @override
  Widget build(BuildContext context) {
    final lineHeight = fontSize * SaturdayType.lineSansBody;
    final gap = fontSize * 0.6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(lines, (i) {
        final isLast = i == lines - 1;
        final line = SaturdaySkeleton.rect(
          width: double.infinity,
          height: fontSize,
        );

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : gap),
          child: SizedBox(
            height: lineHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: isLast
                  ? FractionallySizedBox(
                      widthFactor: lastLineFraction,
                      child: line,
                    )
                  : line,
            ),
          ),
        );
      }),
    );
  }
}
