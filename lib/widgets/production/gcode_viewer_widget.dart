import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'dart:math' as math;

/// A widget that visualizes GCode toolpaths using a custom Canvas-based renderer
/// Optimized for CNC and Laser engraving applications
class GCodeViewerWidget extends StatefulWidget {
  final String gcode;
  final String? fileName;

  const GCodeViewerWidget({
    super.key,
    required this.gcode,
    this.fileName,
  });

  @override
  State<GCodeViewerWidget> createState() => _GCodeViewerWidgetState();
}

class _GCodeViewerWidgetState extends State<GCodeViewerWidget> {
  List<GCodePath> _paths = [];
  GCodeBounds? _bounds;
  int _lineCount = 0;
  bool _isLoading = true;
  String? _error;

  // Zoom and pan state
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _parseGCode();
  }

  @override
  void didUpdateWidget(GCodeViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gcode != oldWidget.gcode) {
      _parseGCode();
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// Parse GCode and extract movement paths
  Future<void> _parseGCode() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Parse in a separate isolate-like manner using Future.delayed to not block UI
      await Future.delayed(Duration.zero);

      final lines = widget.gcode.split('\n');
      _lineCount = lines.length;

      final paths = <GCodePath>[];
      double currentX = 0, currentY = 0, currentZ = 0;
      bool isAbsolute = true; // G90 absolute, G91 relative

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(';') || trimmed.startsWith('(')) {
          continue;
        }

        // Parse movement commands
        if (trimmed.startsWith('G0 ') || trimmed.startsWith('G00 ')) {
          // Rapid movement
          final coords = _parseCoordinates(trimmed, currentX, currentY, currentZ, isAbsolute);
          paths.add(GCodePath(
            startX: currentX,
            startY: currentY,
            endX: coords.x,
            endY: coords.y,
            isRapid: true,
          ));
          currentX = coords.x;
          currentY = coords.y;
          currentZ = coords.z;
        } else if (trimmed.startsWith('G1 ') || trimmed.startsWith('G01 ')) {
          // Linear movement
          final coords = _parseCoordinates(trimmed, currentX, currentY, currentZ, isAbsolute);
          paths.add(GCodePath(
            startX: currentX,
            startY: currentY,
            endX: coords.x,
            endY: coords.y,
            isRapid: false,
          ));
          currentX = coords.x;
          currentY = coords.y;
          currentZ = coords.z;
        } else if (trimmed.startsWith('G90')) {
          // Absolute positioning
          isAbsolute = true;
        } else if (trimmed.startsWith('G91')) {
          // Relative positioning
          isAbsolute = false;
        } else if (trimmed.startsWith('G2 ') || trimmed.startsWith('G02 ') ||
                   trimmed.startsWith('G3 ') || trimmed.startsWith('G03 ')) {
          // Arc movement - simplified as linear for now
          final coords = _parseCoordinates(trimmed, currentX, currentY, currentZ, isAbsolute);
          paths.add(GCodePath(
            startX: currentX,
            startY: currentY,
            endX: coords.x,
            endY: coords.y,
            isRapid: false,
          ));
          currentX = coords.x;
          currentY = coords.y;
          currentZ = coords.z;
        }
      }

      // Calculate bounds
      final bounds = _calculateBounds(paths);

      setState(() {
        _paths = paths;
        _bounds = bounds;
        _isLoading = false;
      });

      // Auto-fit to view
      _resetView();
    } catch (e) {
      setState(() {
        _error = 'Error parsing GCode: $e';
        _isLoading = false;
      });
    }
  }

  /// Parse X, Y, Z coordinates from a GCode line
  _Coordinates _parseCoordinates(
    String line,
    double currentX,
    double currentY,
    double currentZ,
    bool isAbsolute,
  ) {
    double x = currentX;
    double y = currentY;
    double z = currentZ;

    final parts = line.split(' ');
    for (final part in parts) {
      if (part.startsWith('X')) {
        final value = double.tryParse(part.substring(1)) ?? 0;
        x = isAbsolute ? value : currentX + value;
      } else if (part.startsWith('Y')) {
        final value = double.tryParse(part.substring(1)) ?? 0;
        y = isAbsolute ? value : currentY + value;
      } else if (part.startsWith('Z')) {
        final value = double.tryParse(part.substring(1)) ?? 0;
        z = isAbsolute ? value : currentZ + value;
      }
    }

    return _Coordinates(x, y, z);
  }

  /// Calculate bounds of all paths
  GCodeBounds _calculateBounds(List<GCodePath> paths) {
    if (paths.isEmpty) {
      return GCodeBounds(minX: 0, maxX: 100, minY: 0, maxY: 100);
    }

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final path in paths) {
      minX = math.min(minX, math.min(path.startX, path.endX));
      maxX = math.max(maxX, math.max(path.startX, path.endX));
      minY = math.min(minY, math.min(path.startY, path.endY));
      maxY = math.max(maxY, math.max(path.startY, path.endY));
    }

    return GCodeBounds(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );
  }

  /// Reset view to fit all paths
  void _resetView() {
    if (_bounds == null) return;

    // Reset transformation
    _transformController.value = Matrix4.identity();
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  /// Zoom in
  void _zoomIn() {
    setState(() {
      _scale = (_scale * 1.2).clamp(0.1, 10.0);
    });
    _updateTransform();
  }

  /// Zoom out
  void _zoomOut() {
    setState(() {
      _scale = (_scale / 1.2).clamp(0.1, 10.0);
    });
    _updateTransform();
  }

  void _updateTransform() {
    final matrix = Matrix4.identity();
    matrix.translate(_offset.dx, _offset.dy, 0.0);
    matrix.scale(_scale, _scale, 1.0);
    _transformController.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with file info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: SaturdayColors.primaryDark,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.code, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.fileName ?? 'GCode Preview',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$_lineCount lines | ${_paths.length} movements',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                if (_bounds != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Bounds: X(${_bounds!.minX.toStringAsFixed(2)} to ${_bounds!.maxX.toStringAsFixed(2)}) '
                    'Y(${_bounds!.minY.toStringAsFixed(2)} to ${_bounds!.maxY.toStringAsFixed(2)})',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: const Border(
                bottom: BorderSide(color: Colors.grey, width: 1),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _zoomIn,
                  icon: const Icon(Icons.zoom_in),
                  tooltip: 'Zoom In',
                  iconSize: 20,
                ),
                IconButton(
                  onPressed: _zoomOut,
                  icon: const Icon(Icons.zoom_out),
                  tooltip: 'Zoom Out',
                  iconSize: 20,
                ),
                IconButton(
                  onPressed: _resetView,
                  icon: const Icon(Icons.fit_screen),
                  tooltip: 'Reset View',
                  iconSize: 20,
                ),
                const SizedBox(width: 16),
                Text(
                  'Zoom: ${(_scale * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          // Viewer
          Expanded(
            child: _buildViewer(),
          ),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Parsing GCode...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: SaturdayColors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: SaturdayColors.error),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_paths.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 48, color: SaturdayColors.secondaryGrey),
              SizedBox(height: 16),
              Text(
                'No movement commands found in GCode',
                style: TextStyle(color: SaturdayColors.secondaryGrey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.1,
      maxScale: 10.0,
      boundaryMargin: const EdgeInsets.all(100),
      child: CustomPaint(
        painter: GCodePainter(
          paths: _paths,
          bounds: _bounds!,
        ),
        child: Container(),
      ),
    );
  }
}

/// Custom painter for rendering GCode paths
class GCodePainter extends CustomPainter {
  final List<GCodePath> paths;
  final GCodeBounds bounds;

  GCodePainter({
    required this.paths,
    required this.bounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scale to fit bounds in canvas
    const double padding = 40;
    final double availableWidth = size.width - (padding * 2);
    final double availableHeight = size.height - (padding * 2);

    final double boundsWidth = bounds.maxX - bounds.minX;
    final double boundsHeight = bounds.maxY - bounds.minY;

    final double scaleX = boundsWidth > 0 ? availableWidth / boundsWidth : 1;
    final double scaleY = boundsHeight > 0 ? availableHeight / boundsHeight : 1;
    final double scale = math.min(scaleX, scaleY);

    // Transform to canvas coordinates
    Offset transform(double x, double y) {
      final double canvasX = ((x - bounds.minX) * scale) + padding;
      final double canvasY = size.height - (((y - bounds.minY) * scale) + padding); // Flip Y
      return Offset(canvasX, canvasY);
    }

    // Draw bounds rectangle
    final boundsPaint = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final topLeft = transform(bounds.minX, bounds.maxY);
    final bottomRight = transform(bounds.maxX, bounds.minY);
    canvas.drawRect(
      Rect.fromPoints(topLeft, bottomRight),
      boundsPaint,
    );

    // Draw paths
    final rapidPaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final movePaint = Paint()
      ..color = SaturdayColors.info
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final path in paths) {
      final start = transform(path.startX, path.startY);
      final end = transform(path.endX, path.endY);

      canvas.drawLine(
        start,
        end,
        path.isRapid ? rapidPaint : movePaint,
      );
    }

    // Draw origin marker
    final originPaint = Paint()
      ..color = SaturdayColors.error
      ..style = PaintingStyle.fill;

    final origin = transform(0, 0);
    canvas.drawCircle(origin, 4, originPaint);

    // Draw axis labels
    const textStyle = TextStyle(
      color: Colors.black54,
      fontSize: 12,
    );

    _drawText(canvas, 'Origin (0,0)', origin + const Offset(8, -8), textStyle);
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(GCodePainter oldDelegate) {
    return paths != oldDelegate.paths || bounds != oldDelegate.bounds;
  }
}

/// Represents a single GCode path segment
class GCodePath {
  final double startX;
  final double startY;
  final double endX;
  final double endY;
  final bool isRapid;

  GCodePath({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
    required this.isRapid,
  });
}

/// Represents the bounds of the GCode toolpath
class GCodeBounds {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  GCodeBounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
}

/// Helper class for coordinate storage
class _Coordinates {
  final double x;
  final double y;
  final double z;

  _Coordinates(this.x, this.y, this.z);
}
