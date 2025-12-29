import 'package:saturday_consumer_app/utils/epc_validator.dart';

/// Result of parsing a QR code.
sealed class QrParseResult {
  const QrParseResult();
}

/// Successfully parsed a Saturday tag QR code.
class SaturdayTagResult extends QrParseResult {
  final String epc;

  const SaturdayTagResult(this.epc);
}

/// The QR code was valid but not a Saturday tag.
class NonSaturdayQrResult extends QrParseResult {
  final String content;

  const NonSaturdayQrResult(this.content);
}

/// The QR code was invalid or unreadable.
class InvalidQrResult extends QrParseResult {
  final String message;

  const InvalidQrResult(this.message);
}

/// Service for parsing and validating Saturday QR codes.
///
/// Saturday tags have QR codes that encode a URL in the format:
/// https://saturdayvinyl.com/tags/{epc}
///
/// The EPC is a 24-character hexadecimal identifier with prefix "5356".
class QrScannerService {
  /// Parses a QR code string and returns the appropriate result.
  ///
  /// For Saturday tag URLs, extracts and validates the EPC.
  /// For other content, returns a non-Saturday result.
  QrParseResult parseQrCode(String content) {
    if (content.isEmpty) {
      return const InvalidQrResult('Empty QR code');
    }

    // Check if it's a URL
    if (!content.startsWith('http://') && !content.startsWith('https://')) {
      // Not a URL, might be a raw EPC
      if (EpcValidator.isValidSaturdayEpc(content)) {
        return SaturdayTagResult(content.toUpperCase());
      }
      return NonSaturdayQrResult(content);
    }

    // Try to extract EPC from URL
    final epc = EpcValidator.extractEpcFromUrl(content);
    if (epc != null) {
      // Validate it's a Saturday EPC
      if (EpcValidator.isValidSaturdayEpc(epc)) {
        return SaturdayTagResult(epc);
      }
      // Valid format but not Saturday prefix
      return InvalidQrResult('Tag has invalid prefix (not a Saturday tag)');
    }

    // URL but not a Saturday tag URL
    return NonSaturdayQrResult(content);
  }

  /// Validates that a URL is a Saturday tag URL and returns the EPC.
  ///
  /// Returns null if not a valid Saturday tag URL.
  String? extractEpcFromTagUrl(String url) {
    final epc = EpcValidator.extractEpcFromUrl(url);
    if (epc != null && EpcValidator.isValidSaturdayEpc(epc)) {
      return epc;
    }
    return null;
  }

  /// Generates a Saturday tag URL from an EPC.
  String generateTagUrl(String epc) {
    return 'https://saturdayvinyl.com/tags/${epc.toUpperCase()}';
  }
}
