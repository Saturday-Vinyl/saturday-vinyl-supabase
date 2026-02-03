import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Utility for generating unique production unit IDs
class IDGenerator {
  /// Generate a unit ID in the format: SV-{PRODUCT_CODE}-{SEQUENCE}
  /// Example: SV-TURNTABLE-00001
  ///
  /// The sequence number is zero-padded to 5 digits
  static String generateUnitId(String productCode, int sequenceNumber) {
    final paddedSequence = sequenceNumber.toString().padLeft(5, '0');
    return 'SV-$productCode-$paddedSequence';
  }

  /// Get the next sequence number for a product code
  /// Queries the database for the highest sequence number and returns next
  static Future<int> getNextSequenceNumber(String productCode) async {
    try {
      AppLogger.info('Getting next sequence number for product: $productCode');

      final supabase = SupabaseService.instance.client;

      // Query for units with this product code
      // serial_number format: SV-{PRODUCT_CODE}-{SEQUENCE}
      final pattern = 'SV-$productCode-%';

      final response = await supabase
          .from('units')
          .select('serial_number')
          .ilike('serial_number', pattern)
          .order('serial_number', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        AppLogger.info('No existing units for $productCode, starting at 1');
        return 1;
      }

      // Extract sequence number from the last serial number
      final lastSerialNumber = response.first['serial_number'] as String;
      final parts = lastSerialNumber.split('-');

      if (parts.length != 3) {
        AppLogger.warning('Invalid serial number format: $lastSerialNumber, starting at 1');
        return 1;
      }

      final lastSequence = int.tryParse(parts[2]) ?? 0;
      final nextSequence = lastSequence + 1;

      AppLogger.info(
        'Last sequence for $productCode: $lastSequence, next: $nextSequence',
      );

      return nextSequence;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to get next sequence number for $productCode',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Extract product code from unit ID
  /// Example: "SV-TURNTABLE-00001" -> "TURNTABLE"
  static String? extractProductCode(String unitId) {
    final parts = unitId.split('-');
    if (parts.length != 3 || parts[0] != 'SV') {
      return null;
    }
    return parts[1];
  }

  /// Extract sequence number from unit ID
  /// Example: "SV-TURNTABLE-00001" -> 1
  static int? extractSequenceNumber(String unitId) {
    final parts = unitId.split('-');
    if (parts.length != 3 || parts[0] != 'SV') {
      return null;
    }
    return int.tryParse(parts[2]);
  }

  /// Validate unit ID format
  /// Returns true if format matches: SV-{PRODUCT_CODE}-{SEQUENCE}
  static bool validateUnitId(String unitId) {
    final pattern = RegExp(r'^SV-[A-Z0-9]+-\d{5,}$');
    return pattern.hasMatch(unitId);
  }
}
