import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saturday_app/services/image_to_gcode_service.dart';

void main() {
  group('ImageToGCodeService', () {
    late ImageToGCodeService service;

    setUp(() {
      service = ImageToGCodeService();
    });

    test('converts simple black square to gCode', () async {
      // Create 10x10 black square PNG
      final image = img.Image(width: 10, height: 10);
      img.fill(image, color: img.ColorRgb8(0, 0, 0)); // Black

      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final gcode = await service.convertImageToGCode(
        pngData: pngBytes,
        widthMM: 10.0,
        heightMM: 10.0,
        startX: 0.0,
        startY: 0.0,
        maxPower: 100,
        feedRate: 1000,
      );

      expect(gcode, contains('G21')); // Units
      expect(gcode, contains('G90')); // Absolute positioning
      expect(gcode, contains('G91')); // Relative positioning (for scanning)
      expect(gcode, contains('G53')); // Machine coordinate system
      expect(gcode, contains('M4')); // Enable laser (dynamic mode)
      expect(gcode, contains('M5')); // Disable laser
      expect(gcode, contains('S1000')); // Max power for black pixel (0-1000 scale)
      expect(gcode, contains('F1000')); // Feed rate

      // Verify relative positioning format: G1 with X and S on same line
      expect(gcode, contains(RegExp(r'G1 X[\d.-]+S1000')));
    });

    test('converts white square to minimal gCode', () async {
      // Create 10x10 white square PNG
      final image = img.Image(width: 10, height: 10);
      img.fill(image, color: img.ColorRgb8(255, 255, 255)); // White

      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final gcode = await service.convertImageToGCode(
        pngData: pngBytes,
        widthMM: 10.0,
        heightMM: 10.0,
        startX: 0.0,
        startY: 0.0,
        maxPower: 100,
        feedRate: 1000,
      );

      // White pixels should result in S0 or G0 commands (no firing)
      expect(gcode, contains('S0'));
      expect(gcode, contains('M4')); // Still enable laser (dynamic mode)
      expect(gcode, contains('M5')); // Still disable laser
    });

    test('respects start position', () async {
      // Create simple 5x5 black square
      final image = img.Image(width: 5, height: 5);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final gcode = await service.convertImageToGCode(
        pngData: pngBytes,
        widthMM: 5.0,
        heightMM: 5.0,
        startX: 10.0,
        startY: 20.0,
        maxPower: 100,
        feedRate: 1000,
      );

      // Should move to start position using machine coordinates (G53)
      expect(gcode, contains('G53'));
      expect(gcode, contains('X10.000 Y'));
      // Y should be startY + heightMM - stepSize = 20 + 5 - 1 = 24 (top-left, first pixel)
      expect(gcode, contains('Y24.000'));
    });

    test('respects max power setting', () async {
      // Create 5x5 black square
      final image = img.Image(width: 5, height: 5);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));

      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final gcode = await service.convertImageToGCode(
        pngData: pngBytes,
        widthMM: 5.0,
        heightMM: 5.0,
        startX: 0.0,
        startY: 0.0,
        maxPower: 50, // 50% max power
        feedRate: 1000,
      );

      // Should have S500 for black pixels (50% of max on 0-1000 scale)
      expect(gcode, contains('S500'));
      expect(gcode, isNot(contains('S1000'))); // Should not exceed max

      // Verify relative positioning format
      expect(gcode, contains('G91'));
    });

    test('throws error on invalid PNG data', () async {
      final invalidData = Uint8List.fromList([0, 1, 2, 3, 4]);

      expect(
        () async => await service.convertImageToGCode(
          pngData: invalidData,
          widthMM: 10.0,
          heightMM: 10.0,
          startX: 0.0,
          startY: 0.0,
          maxPower: 100,
          feedRate: 1000,
        ),
        throwsA(anything), // Accept any error type
      );
    });

    test('calculates engraving distance correctly', () {
      final distance = service.calculateEngravingDistance(
        imageWidth: 100,
        imageHeight: 100,
        widthMM: 50.0,
        heightMM: 50.0,
      );

      // Should be approximately: (100 rows * 50mm horizontal) + (99 * 0.5mm vertical)
      // = 5000mm + 49.5mm = 5049.5mm
      expect(distance, greaterThan(5000.0));
      expect(distance, lessThan(5100.0));
    });

    test('estimates engraving time correctly', () {
      final time = service.estimateEngravingTime(
        distanceMM: 6000.0, // 6 meters
        feedRate: 1000, // 1000 mm/min = 16.67 mm/sec
      );

      // Should be approximately 6000 / 16.67 = 360 seconds = 6 minutes
      expect(time.inSeconds, greaterThan(350));
      expect(time.inSeconds, lessThan(370));
    });

    test('optimizeGCode returns input unchanged (placeholder)', () {
      const input = 'G1 X10 Y10 S50\nG1 X20 Y20 S50\n';
      final output = service.optimizeGCode(input);

      // Currently just returns input as-is
      expect(output, equals(input));
    });

    test('handles grayscale conversion properly', () async {
      // Create image with varying grayscale values
      final image = img.Image(width: 3, height: 3);
      // Fill with white first
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      // Set different gray levels
      image.setPixel(0, 0, img.ColorRgb8(0, 0, 0)); // Black
      image.setPixel(1, 0, img.ColorRgb8(64, 64, 64)); // Dark gray (will burn at ~50% power)
      image.setPixel(2, 0, img.ColorRgb8(255, 255, 255)); // White

      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final gcode = await service.convertImageToGCode(
        pngData: pngBytes,
        widthMM: 3.0,
        heightMM: 3.0,
        startX: 0.0,
        startY: 0.0,
        maxPower: 100,
        feedRate: 1000,
      );

      // Should have different power levels (0-1000 scale)
      expect(gcode, contains('S1000')); // Black = 100% (1000 on GRBL scale)
      expect(gcode, contains('S510')); // Dark gray ≈ 50% (510 on GRBL scale)
      expect(gcode, contains('S0')); // White = 0%

      // Verify relative positioning format: S on same line as G1
      expect(gcode, contains(RegExp(r'G1 X[\d.-]+S\d+')));
    });
  });
}
