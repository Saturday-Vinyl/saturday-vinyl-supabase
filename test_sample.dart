import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'lib/services/image_to_gcode_service.dart';

void main() async {
  final service = ImageToGCodeService();

  print('=== Test 1: Offset at (10, 20) ===');
  final image1 = img.Image(width: 5, height: 5);
  img.fill(image1, color: img.ColorRgb8(0, 0, 0)); // Black square

  final pngBytes1 = Uint8List.fromList(img.encodePng(image1));

  final gcode1 = await service.convertImageToGCode(
    pngData: pngBytes1,
    widthMM: 5.0,
    heightMM: 5.0,
    startX: 10.0,
    startY: 20.0,
    maxPower: 100,
    feedRate: 1000,
  );

  // Should see G53 G0 X10.000 Y24.000
  print('First move: ${gcode1.split('\n').where((line) => line.contains('G53 G0')).first}');

  print('\n=== Test 2: Offset at (40, 40) ===');
  final gcode2 = await service.convertImageToGCode(
    pngData: pngBytes1,
    widthMM: 35.0,
    heightMM: 35.0,
    startX: 40.0,
    startY: 40.0,
    maxPower: 100,
    feedRate: 1000,
  );

  // Should see G53 G0 X40.000 Y68.000 (40 + 35 - 7 = 68)
  print('First move: ${gcode2.split('\n').where((line) => line.contains('G53 G0')).first}');

  print('\nNote: G53 forces machine coordinates, ignoring any work coordinate offsets');
}
