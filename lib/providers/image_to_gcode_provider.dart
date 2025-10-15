import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/services/image_to_gcode_service.dart';

/// Provider for ImageToGCodeService
final imageToGCodeServiceProvider = Provider<ImageToGCodeService>((ref) {
  return ImageToGCodeService();
});
