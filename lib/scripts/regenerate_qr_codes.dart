import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Script to regenerate QR codes for existing production units with new branded design
///
/// This script:
/// 1. Loads the specified production unit UUIDs
/// 2. Generates new branded QR codes with the Saturday logo
/// 3. Uploads them to Supabase storage (overwrites existing)
/// 4. Updates complete - no database changes needed as the file path remains the same
///
/// Usage:
/// Run this from a Flutter app context (e.g., in a debug screen or via main.dart)
Future<void> regenerateQRCodes(List<String> uuids) async {
  final qrService = QRService();
  final supabase = SupabaseService.instance.client;

  AppLogger.info('Starting QR code regeneration for ${uuids.length} units');

  for (final uuid in uuids) {
    try {
      AppLogger.info('Regenerating QR code for UUID: $uuid');

      // Generate new branded QR code
      final qrImageData = await qrService.generateQRCode(
        uuid,
        size: 512,
        embedLogo: true,
      );

      AppLogger.info('QR code generated, size: ${qrImageData.length} bytes');

      // Upload to Supabase storage (remove old file first if it exists)
      final filePath = 'qr-codes/$uuid.png';

      try {
        // Try to remove existing file
        await supabase.storage.from('qr-codes').remove([filePath]);
        AppLogger.info('Removed existing QR code');
      } catch (e) {
        // File might not exist, that's OK
        AppLogger.info('No existing QR code to remove (or removal failed)');
      }

      // Upload new QR code
      await supabase.storage
          .from('qr-codes')
          .uploadBinary(filePath, qrImageData);

      AppLogger.info('✓ Successfully regenerated QR code for $uuid');
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to regenerate QR code for $uuid',
        error,
        stackTrace,
      );
    }
  }

  AppLogger.info('QR code regeneration complete');
}

/// Main entry point for the script
/// Regenerates QR codes for the two existing production units
Future<void> main() async {
  // Initialize Supabase before running
  // await SupabaseService.instance.initialize();

  final uuids = [
    '51807ce2-11ab-41e0-8900-e1e1c5bae9bd',
    'ee7736c1-a48b-4b5d-8498-6f811634aea5',
  ];

  await regenerateQRCodes(uuids);
}
