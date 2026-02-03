import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/services/qr_code_fetch_service.dart';

/// Service for converting PNG images to gCode for laser engraving
class ImageToGCodeService {
  /// Convert PNG image to raster-scanned gCode
  ///
  /// Parameters:
  /// - [pngData]: Raw PNG image bytes
  /// - [widthMM]: Physical width of the engraving in millimeters
  /// - [heightMM]: Physical height of the engraving in millimeters
  /// - [startX]: Starting X position in millimeters
  /// - [startY]: Starting Y position in millimeters
  /// - [maxPower]: Maximum laser power percentage (0-100)
  /// - [feedRate]: Laser movement speed in mm/min
  /// - [threshold]: Grayscale threshold (0-255). Pixels lighter than this value will be skipped. Default 128 (mid-gray)
  /// - [invert]: If true, lighter pixels = more power. If false, darker pixels = more power. Default false.
  Future<String> convertImageToGCode({
    required Uint8List pngData,
    required double widthMM,
    required double heightMM,
    required double startX,
    required double startY,
    required int maxPower,
    required int feedRate,
    int threshold = 128,
    bool invert = false,
  }) async {
    try {
      // 1. Decode PNG
      final image = img.decodeImage(pngData);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      AppLogger.info(
          'Converting ${image.width}x${image.height} image to gCode');

      // 2. Handle transparency - convert transparent pixels to white
      // This is critical for QR codes which often have transparent backgrounds
      final processedImage = img.Image(width: image.width, height: image.height);

      // Fill with white background
      img.fill(processedImage, color: img.ColorRgb8(255, 255, 255));

      // Composite original image on top (this handles alpha blending)
      img.compositeImage(processedImage, image);

      AppLogger.info('Processed transparency: transparent pixels converted to white');

      // 3. Convert to grayscale
      final grayscale = img.grayscale(processedImage);

      // 4. Calculate step size (mm per pixel)
      final stepSizeXMM = widthMM / grayscale.width;
      final stepSizeYMM = heightMM / grayscale.height;

      AppLogger.info(
          'Step size: X=${stepSizeXMM.toStringAsFixed(4)}mm, Y=${stepSizeYMM.toStringAsFixed(4)}mm');

      // 5. Generate gCode
      final gcode = StringBuffer();

      // Header
      gcode.writeln('; Generated QR Code Engraving gCode');
      gcode.writeln(
          '; Image size: ${grayscale.width}x${grayscale.height} pixels');
      gcode.writeln(
          '; Physical size: ${widthMM.toStringAsFixed(2)}mm x ${heightMM.toStringAsFixed(2)}mm');
      gcode.writeln(
          '; Max power: $maxPower%, Feed rate: ${feedRate}mm/min');
      gcode.writeln('; Threshold: $threshold, Invert: $invert');
      gcode.writeln();

      // Initialize
      gcode.writeln('G21 ; Set units to millimeters');
      gcode.writeln('G90 ; Absolute positioning');
      gcode.writeln('M4 ; Enable laser (dynamic power mode)');
      gcode.writeln('S0 ; Laser off initially');
      gcode.writeln('F$feedRate ; Set feed rate');
      gcode.writeln();

      // Move to start position using machine coordinates (G53 ignores work coordinate offsets)
      // Start at top-left (highest Y position)
      final startYTop = startY + heightMM - stepSizeYMM;
      gcode.writeln(
          'G53 G0 X${startX.toStringAsFixed(3)} Y${startYTop.toStringAsFixed(3)} ; Move to start (machine coordinates)');
      gcode.writeln();

      // Switch to relative positioning for efficient scanning
      gcode.writeln('G91 ; Relative positioning');
      gcode.writeln();

      // Raster scan
      bool leftToRight = true;

      for (int y = 0; y < grayscale.height; y++) {
        gcode.writeln('; Row $y');

        // Build optimized row data by combining consecutive pixels with same power
        final rowMoves = _buildOptimizedRow(
          grayscale: grayscale,
          y: y,
          leftToRight: leftToRight,
          stepSizeXMM: stepSizeXMM,
          maxPower: maxPower,
          threshold: threshold,
          invert: invert,
        );

        // Output row moves
        for (final move in rowMoves) {
          gcode.writeln(move);
        }

        // Move to next row (relative Y movement)
        if (y < grayscale.height - 1) {
          gcode.writeln('G1 Y${(-stepSizeYMM).toStringAsFixed(3)}');
          // No X return needed - bidirectional scanning means next row scans back
        }

        leftToRight = !leftToRight; // Alternate direction
      }

      // Footer
      gcode.writeln();
      gcode.writeln('S0 ; Laser off');
      gcode.writeln('M5 ; Disable laser');
      gcode.writeln('G90 ; Return to absolute positioning');
      gcode.writeln(
          'G53 G0 X${startX.toStringAsFixed(3)} Y${startY.toStringAsFixed(3)} ; Return to start (machine coordinates)');
      gcode.writeln('; End of gCode');

      final gcodeString = gcode.toString();
      final lineCount = gcodeString.split('\n').length;

      AppLogger.info('Generated $lineCount lines of gCode');

      return gcodeString;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to convert image to gCode', e, stackTrace);
      rethrow;
    }
  }

  /// Build optimized row moves by combining consecutive pixels with same power
  ///
  /// Returns list of gcode commands for scanning one row
  List<String> _buildOptimizedRow({
    required img.Image grayscale,
    required int y,
    required bool leftToRight,
    required double stepSizeXMM,
    required int maxPower,
    required int threshold,
    required bool invert,
  }) {
    final moves = <String>[];

    // Determine scan direction
    final xRange = leftToRight
        ? Iterable<int>.generate(grayscale.width, (i) => i)
        : Iterable<int>.generate(grayscale.width, (i) => grayscale.width - 1 - i);

    // Track current segment
    int? currentPower;
    double segmentDistance = 0.0;
    final direction = leftToRight ? 1.0 : -1.0;

    for (final x in xRange) {
      final pixel = grayscale.getPixel(x, y);
      final intensity = pixel.r.toInt(); // 0-255

      // Determine if we should burn this pixel
      final bool shouldBurn = invert
          ? intensity > threshold
          : intensity < threshold;

      // Calculate power for this pixel
      int pixelPower = 0;
      if (shouldBurn) {
        final double normalizedIntensity;
        if (invert) {
          normalizedIntensity = (intensity - threshold) / (255.0 - threshold);
        } else {
          normalizedIntensity = 1.0 - (intensity / threshold);
        }
        pixelPower = (normalizedIntensity * maxPower).round().clamp(1, maxPower);
      }

      // Check if we need to output current segment and start new one
      if (currentPower != null && currentPower != pixelPower) {
        // Output accumulated segment
        final relativeX = direction * segmentDistance;
        // Convert power from 0-100 scale to 0-1000 scale for GRBL
        final grblPower = (currentPower * 10).round();
        moves.add('G1 X${relativeX.toStringAsFixed(3)}S$grblPower');

        // Start new segment
        currentPower = pixelPower;
        segmentDistance = stepSizeXMM;
      } else {
        // Continue accumulating
        if (currentPower == null) {
          currentPower = pixelPower;
        }
        segmentDistance += stepSizeXMM;
      }
    }

    // Output final segment
    if (currentPower != null && segmentDistance > 0) {
      final relativeX = direction * segmentDistance;
      // Convert power from 0-100 scale to 0-1000 scale for GRBL
      final grblPower = (currentPower * 10).round();
      moves.add('G1 X${relativeX.toStringAsFixed(3)}S$grblPower');
    }

    return moves;
  }

  /// Optimize gCode by combining consecutive moves with same power
  ///
  /// Optional optimization pass to reduce file size and improve performance.
  /// Currently returns the input unchanged - can be implemented if needed.
  String optimizeGCode(String gcode) {
    // Optional optimization pass
    // Combine consecutive G1 commands with same S value
    // Skip for v1, implement if performance issues
    return gcode;
  }

  /// Estimate engraving time based on distance and feed rate
  ///
  /// Parameters:
  /// - [distanceMM]: Total distance to travel in millimeters
  /// - [feedRate]: Laser movement speed in mm/min
  Duration estimateEngravingTime({
    required double distanceMM,
    required int feedRate,
  }) {
    // Calculate time: distance / speed (converted from mm/min to mm/sec)
    final seconds = (distanceMM / (feedRate / 60)).round();
    return Duration(seconds: seconds);
  }

  /// Calculate total engraving distance for an image
  ///
  /// Estimates the total distance the laser head will travel
  double calculateEngravingDistance({
    required int imageWidth,
    required int imageHeight,
    required double widthMM,
    required double heightMM,
  }) {
    final stepSizeXMM = widthMM / imageWidth;
    final stepSizeYMM = heightMM / imageHeight;

    // Horizontal distance per row
    final rowDistance = imageWidth * stepSizeXMM;

    // Total horizontal distance for all rows
    final totalHorizontalDistance = rowDistance * imageHeight;

    // Vertical distance between rows
    final totalVerticalDistance = (imageHeight - 1) * stepSizeYMM;

    // Total distance (approximate)
    return totalHorizontalDistance + totalVerticalDistance;
  }

  /// Generate gCode from production unit's QR code
  ///
  /// Fetches the QR code image from storage and converts it to laser engraving gCode
  /// using the parameters defined in the production step.
  Future<String> generateQREngraveGCode({
    required Unit unit,
    required ProductionStep step,
  }) async {
    // Validate step has engraving config
    if (!step.engraveQr) {
      throw Exception('QR engraving not enabled for this step');
    }

    // Validate required parameters
    if (step.qrSize == null ||
        step.qrXOffset == null ||
        step.qrYOffset == null ||
        step.qrPowerPercent == null ||
        step.qrSpeedMmMin == null) {
      throw Exception('QR engraving parameters not configured for this step');
    }

    try {
      AppLogger.info('Generating QR engrave gCode for unit: ${unit.serialNumber ?? 'Unknown'}');

      if (unit.qrCodeUrl == null) {
        throw Exception('Unit has no QR code URL');
      }

      // Fetch QR code image from Supabase
      final qrFetchService = QRCodeFetchService(Supabase.instance.client);
      final pngData = await qrFetchService.fetchQRCodeImage(unit.qrCodeUrl!);

      AppLogger.info('Fetched QR code image: ${pngData.length} bytes');

      // Convert to gCode using step parameters
      final gcode = await convertImageToGCode(
        pngData: pngData,
        widthMM: step.qrSize!,
        heightMM: step.qrSize!, // QR codes are square
        startX: step.qrXOffset!,
        startY: step.qrYOffset!,
        maxPower: step.qrPowerPercent!,
        feedRate: step.qrSpeedMmMin!,
      );

      AppLogger.info('Generated QR engrave gCode: ${gcode.split('\n').length} lines');

      return gcode;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to generate QR engrave gCode', e, stackTrace);
      rethrow;
    }
  }
}
