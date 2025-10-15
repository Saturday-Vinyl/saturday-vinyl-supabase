import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'lib/services/image_to_gcode_service.dart';

void main() async {
  final service = ImageToGCodeService();
  
  // Create 5x5 test pattern
  final image = img.Image(width: 5, height: 5);
  img.fill(image, color: img.ColorRgb8(255, 255, 255)); // White
  
  // Create simple pattern: black corners
  image.setPixel(0, 0, img.ColorRgb8(0, 0, 0));
  image.setPixel(4, 0, img.ColorRgb8(0, 0, 0));
  image.setPixel(0, 4, img.ColorRgb8(0, 0, 0));
  image.setPixel(4, 4, img.ColorRgb8(0, 0, 0));
  
  final pngBytes = Uint8List.fromList(img.encodePng(image));
  
  final gcode = await service.convertImageToGCode(
    pngData: pngBytes,
    widthMM: 5.0,
    heightMM: 5.0,
    startX: 0.0,
    startY: 0.0,
    maxPower: 100,
    feedRate: 1000,
  );
  
  print(gcode);
}
