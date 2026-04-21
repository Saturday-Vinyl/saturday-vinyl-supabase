import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/slot_editor_state_provider.dart';
import 'package:saturday_app/utils/perspective_transform.dart';

/// Interactive canvas for the WYSIWYG slot editor.
///
/// Renders the product frame image with draggable transform/clip overlays
/// and a live perspective-transformed album preview.
class SlotEditorCanvas extends ConsumerStatefulWidget {
  final ui.Image? frameImage;
  final ui.Image? sampleAlbumImage;
  final int imageWidth;
  final int imageHeight;

  const SlotEditorCanvas({
    super.key,
    required this.frameImage,
    required this.sampleAlbumImage,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  ConsumerState<SlotEditorCanvas> createState() => _SlotEditorCanvasState();
}

class _SlotEditorCanvasState extends ConsumerState<SlotEditorCanvas> {
  final _transformationController = TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Offset _toImageCoords(Offset screenPos, double scale) {
    // Invert the InteractiveViewer transform then convert to image space
    final viewerMatrix = _transformationController.value.clone();
    final inverse = Matrix4.inverted(viewerMatrix);
    final scenePoint =
        MatrixUtils.transformPoint(inverse, screenPos);
    return Offset(scenePoint.dx / scale, scenePoint.dy / scale);
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(slotEditorProvider);
    final notifier = ref.read(slotEditorProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / widget.imageWidth;
        final scaleY = constraints.maxHeight / widget.imageHeight;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final canvasSize =
            Size(widget.imageWidth * scale, widget.imageHeight * scale);

        return Container(
          color: Colors.grey.shade900,
          child: Center(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 5.0,
              constrained: false,
              child: Listener(
                onPointerDown: (event) {
                  if (editorState.mode == SlotEditorMode.preview) return;
                  final imagePos = _toImageCoords(event.localPosition, scale);
                  notifier.onPointerDown(imagePos);
                },
                onPointerMove: (event) {
                  if (editorState.mode == SlotEditorMode.preview) return;
                  final imagePos = _toImageCoords(event.localPosition, scale);
                  notifier.onPointerMove(imagePos);
                },
                onPointerUp: (_) => notifier.onPointerUp(),
                child: CustomPaint(
                  size: canvasSize,
                  painter: _SlotEditorPainter(
                    frameImage: widget.frameImage,
                    sampleAlbumImage: widget.sampleAlbumImage,
                    state: editorState,
                    scale: scale,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlotEditorPainter extends CustomPainter {
  final ui.Image? frameImage;
  final ui.Image? sampleAlbumImage;
  final SlotEditorState state;
  final double scale;

  _SlotEditorPainter({
    required this.frameImage,
    required this.sampleAlbumImage,
    required this.state,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    // In preview mode: clip first, then draw album, then frame on top
    if (state.mode == SlotEditorMode.preview) {
      _drawPreviewComposite(canvas, size);
    } else {
      // Draw frame image as the background
      _drawFrameImage(canvas);

      // Draw album ON TOP of the frame with transparency so it's visible
      // while editing (frame is likely fully opaque)
      if (state.mode == SlotEditorMode.transform && sampleAlbumImage != null) {
        _drawTransformedAlbum(canvas, opacity: 0.6);
        _drawQuadOutline(canvas, state.transformCorners);
        _drawHandles(canvas, state.transformCorners);
      }

      if (state.mode == SlotEditorMode.clip && sampleAlbumImage != null) {
        // Show the album clipped to the polygon so user sees the visible area
        _drawClippedAlbum(canvas, opacity: 0.6);
        _drawClipPolygon(canvas);
        _drawHandles(canvas, state.clipPoints);
      } else if (state.mode == SlotEditorMode.clip) {
        _drawClipPolygon(canvas);
        _drawHandles(canvas, state.clipPoints);
      }
    }

    canvas.restore();
  }

  void _drawFrameImage(Canvas canvas) {
    if (frameImage == null) return;
    canvas.save();
    canvas.scale(scale);
    canvas.drawImage(frameImage!, Offset.zero, Paint());
    canvas.restore();
  }

  void _drawTransformedAlbum(Canvas canvas, {double opacity = 1.0}) {
    if (sampleAlbumImage == null) {
      debugPrint('_drawTransformedAlbum: sampleAlbumImage is null');
      return;
    }
    if (state.transformCorners.length != 4) {
      debugPrint('_drawTransformedAlbum: corners=${state.transformCorners.length}');
      return;
    }
    try {
      final matrix = PerspectiveTransform.compute(
        srcWidth: sampleAlbumImage!.width.toDouble(),
        srcHeight: sampleAlbumImage!.height.toDouble(),
        dst: state.transformCorners,
      );

      final m4 = matrix.toMatrix4();

      canvas.save();
      canvas.scale(scale);
      canvas.transform(m4.storage);
      canvas.drawImage(
        sampleAlbumImage!,
        Offset.zero,
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
      );
      canvas.restore();
    } catch (e) {
      // Degenerate quad — log and skip rendering
      debugPrint('Perspective transform failed: $e');
    }
  }

  /// Draw the album perspective-transformed and clipped to the clip polygon.
  /// Used in clip mode so the user sees exactly what area is visible.
  void _drawClippedAlbum(Canvas canvas, {double opacity = 1.0}) {
    if (sampleAlbumImage == null) return;
    if (state.transformCorners.length != 4) return;
    if (state.clipPoints.length < 3) return;

    try {
      final matrix = PerspectiveTransform.compute(
        srcWidth: sampleAlbumImage!.width.toDouble(),
        srcHeight: sampleAlbumImage!.height.toDouble(),
        dst: state.transformCorners,
      );

      // Build clip path in screen space
      final clipPath = Path();
      final scaledClip = state.clipPoints.map((p) => p * scale).toList();
      clipPath.moveTo(scaledClip.first.dx, scaledClip.first.dy);
      for (final p in scaledClip.skip(1)) {
        clipPath.lineTo(p.dx, p.dy);
      }
      clipPath.close();

      canvas.save();
      canvas.clipPath(clipPath);
      canvas.scale(scale);
      canvas.transform(matrix.toMatrix4().storage);
      canvas.drawImage(
        sampleAlbumImage!,
        Offset.zero,
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
      );
      canvas.restore();
    } catch (e) {
      debugPrint('Clipped album transform failed: $e');
    }
  }

  void _drawClipPolygon(Canvas canvas) {
    if (state.clipPoints.length < 3) return;

    final path = Path();
    final scaled = state.clipPoints.map((p) => p * scale).toList();
    path.moveTo(scaled.first.dx, scaled.first.dy);
    for (final p in scaled.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();

    // Semi-transparent fill
    canvas.drawPath(
      path,
      Paint()
        ..color = SaturdayColors.info.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // Stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = SaturdayColors.info
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  void _drawPreviewComposite(Canvas canvas, Size size) {
    if (state.clipPoints.length < 3 || state.transformCorners.length != 4) {
      _drawFrameImage(canvas);
      return;
    }

    // Build clip path in screen space
    final clipPath = Path();
    final scaledClip = state.clipPoints.map((p) => p * scale).toList();
    clipPath.moveTo(scaledClip.first.dx, scaledClip.first.dy);
    for (final p in scaledClip.skip(1)) {
      clipPath.lineTo(p.dx, p.dy);
    }
    clipPath.close();

    // Step 1: Draw the album (transformed + clipped to polygon)
    if (sampleAlbumImage != null) {
      try {
        canvas.save();
        canvas.clipPath(clipPath);
        canvas.scale(scale);
        final matrix = PerspectiveTransform.compute(
          srcWidth: sampleAlbumImage!.width.toDouble(),
          srcHeight: sampleAlbumImage!.height.toDouble(),
          dst: state.transformCorners,
        );
        canvas.transform(matrix.toMatrix4().storage);
        canvas.drawImage(sampleAlbumImage!, Offset.zero, Paint());
        canvas.restore();
      } catch (e) {
        debugPrint('Preview transform failed: $e');
      }
    }

    // Step 2: Draw the product image with clip area punched out,
    // so the album underneath shows through.
    // saveLayer isolates BlendMode.clear to this layer only.
    canvas.saveLayer(Offset.zero & size, Paint());
    _drawFrameImage(canvas);
    canvas.drawPath(clipPath, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  void _drawQuadOutline(Canvas canvas, List<Offset> points) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = SaturdayColors.info
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < points.length; i++) {
      final next = (i + 1) % points.length;
      canvas.drawLine(
        points[i] * scale,
        points[next] * scale,
        paint,
      );
    }
  }

  void _drawHandles(Canvas canvas, List<Offset> points) {
    for (int i = 0; i < points.length; i++) {
      final screenPos = points[i] * scale;
      final isActive = state.dragIndex == i;

      // White outer circle
      canvas.drawCircle(
        screenPos,
        isActive ? 14 : 10,
        Paint()
          ..color = SaturdayColors.white
          ..style = PaintingStyle.fill,
      );

      // Colored inner circle
      canvas.drawCircle(
        screenPos,
        isActive ? 10 : 7,
        Paint()
          ..color = isActive ? SaturdayColors.warning : SaturdayColors.info
          ..style = PaintingStyle.fill,
      );

      // Index label
      final tp = TextPainter(
        text: TextSpan(
          text: '$i',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        screenPos - Offset(tp.width / 2, tp.height / 2),
      );

      // Coordinate label below handle
      final coordTp = TextPainter(
        text: TextSpan(
          text:
              '(${points[i].dx.toStringAsFixed(0)}, ${points[i].dy.toStringAsFixed(0)})',
          style: TextStyle(
            color: SaturdayColors.white.withValues(alpha: 0.8),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      coordTp.paint(
        canvas,
        screenPos + Offset(-coordTp.width / 2, (isActive ? 14 : 10) + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SlotEditorPainter old) =>
      old.state != state ||
      old.frameImage != frameImage ||
      old.sampleAlbumImage != sampleAlbumImage;
}
