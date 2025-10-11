import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for scanning QR codes and extracting UUIDs
class QRScannerService {
  final _qrService = QRService();

  /// Parse scanned QR code text and extract UUID
  /// Throws FormatException if invalid
  Future<String> processScannedCode(String scannedText) async {
    try {
      AppLogger.info('Processing scanned QR code: $scannedText');

      // Use QRService to parse and validate
      final uuid = _qrService.parseQRCode(scannedText);

      AppLogger.info('Successfully extracted UUID: $uuid');
      return uuid;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to process scanned code', error, stackTrace);
      rethrow;
    }
  }

  /// Validate that a scanned string looks like a QR code URL
  bool looksLikeQRCode(String text) {
    // Check if it starts with http:// or https://
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      return false;
    }

    // Check if it contains /unit/
    if (!text.contains('/unit/')) {
      return false;
    }

    return true;
  }
}
