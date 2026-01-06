/// Utilities for validating and formatting Saturday RFID EPC identifiers.
///
/// Saturday EPCs follow a specific format:
/// - 24 hexadecimal characters
/// - Prefix: "5356" (Saturday vendor code)
class EpcValidator {
  EpcValidator._();

  /// The Saturday vendor prefix for EPCs.
  static const String saturdayPrefix = '5356';

  /// Expected length of a valid EPC.
  static const int epcLength = 24;

  /// Regular expression for valid hex characters.
  static final _hexPattern = RegExp(r'^[0-9A-Fa-f]+$');

  /// Validates that an EPC is a valid Saturday EPC.
  ///
  /// Returns true if:
  /// - EPC is exactly 24 characters
  /// - Contains only hexadecimal characters
  /// - Starts with the Saturday prefix "5356"
  static bool isValidSaturdayEpc(String epc) {
    if (epc.length != epcLength) return false;
    if (!_hexPattern.hasMatch(epc)) return false;
    if (!epc.toUpperCase().startsWith(saturdayPrefix)) return false;
    return true;
  }

  /// Validates that an EPC has the correct format (ignoring prefix).
  ///
  /// Returns true if:
  /// - EPC is exactly 24 characters
  /// - Contains only hexadecimal characters
  static bool isValidEpcFormat(String epc) {
    return epc.length == epcLength && _hexPattern.hasMatch(epc);
  }

  /// Formats an EPC for display by adding dashes every 4 characters.
  ///
  /// Example: "535600000001000000000001" -> "5356-0000-0001-0000-0000-0001"
  static String formatEpcForDisplay(String epc) {
    if (epc.isEmpty) return epc;

    final buffer = StringBuffer();
    for (int i = 0; i < epc.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(epc[i].toUpperCase());
    }
    return buffer.toString();
  }

  /// Removes formatting from a display EPC.
  ///
  /// Removes dashes, spaces, and converts to uppercase.
  static String normalizeEpc(String displayEpc) {
    return displayEpc.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
  }

  /// Extracts the EPC from a Saturday QR code URL.
  ///
  /// Expected URL format: https://app.saturdayvinyl.com/tags/{epc}
  /// Returns null if the URL doesn't match the expected format.
  static String? extractEpcFromUrl(String url) {
    try {
      final uri = Uri.parse(url);

      // Check for valid Saturday domains
      final validDomains = ['app.saturdayvinyl.com'];
      if (!validDomains.contains(uri.host)) {
        return null;
      }

      // Check path format
      final pathSegments = uri.pathSegments;
      if (pathSegments.length != 2 || pathSegments[0] != 'tags') {
        return null;
      }

      final epc = pathSegments[1].toUpperCase();
      return isValidEpcFormat(epc) ? epc : null;
    } catch (e) {
      return null;
    }
  }

  /// Returns an error message for an invalid EPC, or null if valid.
  static String? getValidationError(String epc) {
    if (epc.isEmpty) {
      return 'EPC is required';
    }
    if (epc.length != epcLength) {
      return 'EPC must be exactly $epcLength characters (got ${epc.length})';
    }
    if (!_hexPattern.hasMatch(epc)) {
      return 'EPC must contain only hexadecimal characters (0-9, A-F)';
    }
    if (!epc.toUpperCase().startsWith(saturdayPrefix)) {
      return 'Not a Saturday tag (invalid prefix)';
    }
    return null;
  }
}
