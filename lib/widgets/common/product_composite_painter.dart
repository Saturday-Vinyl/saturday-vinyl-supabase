import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// CustomPainter that composites album cover art into a product frame image
/// using a perspective transform and clip path.
///
/// Rendering order:
/// 1. Album cover is perspective-transformed into the slot quad and clipped
/// 2. Product frame is drawn on top with the clip area cleared so the album
///    shows through
///
/// All coordinates in [transformCorners] and [clipPoints] are specified in
/// source image pixels and are automatically scaled to the widget size.
class ProductCompositePainter extends CustomPainter {
  final ui.Image frameImage;
  final ui.Image? albumImage;

  /// 4 destination corners (TL, TR, BR, BL) in source image pixel coordinates
  /// defining the perspective quad for the album cover.
  final List<Offset>? transformCorners;

  /// N-point polygon in source image pixel coordinates defining the visible
  /// area (occlusion clip). Parts of the album outside this polygon are hidden
  /// by the product frame.
  final List<Offset>? clipPoints;

  ProductCompositePainter({
    required this.frameImage,
    this.albumImage,
    this.transformCorners,
    this.clipPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;

    final frameSrc = Rect.fromLTWH(
      0,
      0,
      frameImage.width.toDouble(),
      frameImage.height.toDouble(),
    );
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    final canComposite = albumImage != null &&
        transformCorners != null &&
        transformCorners!.length == 4 &&
        clipPoints != null &&
        clipPoints!.length >= 3;

    if (canComposite) {
      // Scale factors from source image coordinates to widget coordinates
      final scaleX = size.width / frameImage.width;
      final scaleY = size.height / frameImage.height;

      // Scale transform corners to widget space
      final dst = transformCorners!
          .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
          .toList();

      // Build clip path in widget space
      final clipPath = Path();
      final scaledClip = clipPoints!
          .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
          .toList();
      clipPath.moveTo(scaledClip[0].dx, scaledClip[0].dy);
      for (var i = 1; i < scaledClip.length; i++) {
        clipPath.lineTo(scaledClip[i].dx, scaledClip[i].dy);
      }
      clipPath.close();

      // Step 1: Draw album cover, perspective-transformed and clipped
      canvas.save();
      canvas.clipPath(clipPath);

      final matrix = _computePerspectiveMatrix(
        albumImage!.width.toDouble(),
        albumImage!.height.toDouble(),
        dst,
      );
      canvas.transform(matrix);
      canvas.drawImage(albumImage!, Offset.zero, paint);
      canvas.restore();

      // Step 2: Draw frame with clip area cleared so album shows through
      canvas.saveLayer(dstRect, Paint());
      canvas.drawImageRect(frameImage, frameSrc, dstRect, paint);
      canvas.drawPath(
        clipPath,
        Paint()..blendMode = BlendMode.clear,
      );
      canvas.restore();
    } else {
      // No compositing — just draw the product frame
      canvas.drawImageRect(frameImage, frameSrc, dstRect, paint);
    }
  }

  /// Computes a 4x4 perspective transform matrix that maps a rectangle
  /// of [srcW] x [srcH] to the quadrilateral defined by [dst] (4 corners:
  /// TL, TR, BR, BL).
  Float64List _computePerspectiveMatrix(
    double srcW,
    double srcH,
    List<Offset> dst,
  ) {
    // Solve for the 3x3 projective matrix mapping unit square to dst quad,
    // then pre-multiply by the source rect → unit square scaling.
    //
    // Unit square corners: (0,0), (1,0), (1,1), (0,1)
    // Destination corners: dst[0..3] = TL, TR, BR, BL

    final x0 = dst[0].dx, y0 = dst[0].dy;
    final x1 = dst[1].dx, y1 = dst[1].dy;
    final x2 = dst[2].dx, y2 = dst[2].dy;
    final x3 = dst[3].dx, y3 = dst[3].dy;

    final dx1 = x1 - x2;
    final dx2 = x3 - x2;
    final dx3 = x0 - x1 + x2 - x3;
    final dy1 = y1 - y2;
    final dy2 = y3 - y2;
    final dy3 = y0 - y1 + y2 - y3;

    final den = dx1 * dy2 - dx2 * dy1;

    final g = (dx3 * dy2 - dx2 * dy3) / den;
    final h = (dx1 * dy3 - dx3 * dy1) / den;

    final a = x1 - x0 + g * x1;
    final b = x3 - x0 + h * x3;
    final c = x0;
    final d = y1 - y0 + g * y1;
    final e = y3 - y0 + h * y3;
    final f = y0;

    // 3x3 projective matrix (maps unit square → dst quad):
    // [a b c]
    // [d e f]
    // [g h 1]
    //
    // Pre-multiply by source rect → unit square: scale(1/srcW, 1/srcH)
    // Combined: multiply columns 0,1 of the 3x3 by 1/srcW, 1/srcH respectively
    final m = vm.Matrix4.zero();
    // Column 0 (x basis, scaled by 1/srcW)
    m.setEntry(0, 0, a / srcW);
    m.setEntry(1, 0, d / srcW);
    m.setEntry(3, 0, g / srcW);
    // Column 1 (y basis, scaled by 1/srcH)
    m.setEntry(0, 1, b / srcH);
    m.setEntry(1, 1, e / srcH);
    m.setEntry(3, 1, h / srcH);
    // Column 2 (z — identity for 2D)
    m.setEntry(2, 2, 1.0);
    // Column 3 (translation)
    m.setEntry(0, 3, c);
    m.setEntry(1, 3, f);
    m.setEntry(3, 3, 1.0);

    return m.storage;
  }

  @override
  bool shouldRepaint(ProductCompositePainter oldDelegate) {
    return frameImage != oldDelegate.frameImage ||
        albumImage != oldDelegate.albumImage ||
        transformCorners != oldDelegate.transformCorners ||
        clipPoints != oldDelegate.clipPoints;
  }
}
