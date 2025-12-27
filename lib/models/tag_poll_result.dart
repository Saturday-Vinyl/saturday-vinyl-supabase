import 'package:equatable/equatable.dart';
import 'package:saturday_app/config/rfid_config.dart';

/// Result from polling for a single RFID tag
///
/// Contains the EPC, RSSI, and convenience methods for
/// identifying Saturday Vinyl tags.
class TagPollResult extends Equatable {
  /// EPC identifier as raw bytes
  final List<int> epc;

  /// Received Signal Strength Indicator
  /// Higher values indicate stronger signal (closer tag)
  final int rssi;

  /// Protocol Control bits from the tag
  final int pc;

  /// Timestamp when the tag was detected
  final DateTime timestamp;

  TagPollResult({
    required this.epc,
    required this.rssi,
    this.pc = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Get EPC as uppercase hex string (no separators)
  String get epcHex =>
      epc.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();

  /// Get EPC formatted with dashes for readability
  ///
  /// Format: 5356-XXXX-XXXX-XXXX-XXXX-XXXX (for 96-bit EPC)
  String get formattedEpc {
    final hex = epcHex;
    if (hex.length != 24) return hex;
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 24)}';
  }

  /// Check if this is a Saturday Vinyl tag
  ///
  /// A valid Saturday tag must:
  /// 1. Start with "SV" / 0x5356 prefix
  /// 2. Be exactly 96-bit / 12 bytes / 24 hex chars
  bool get isSaturdayTag =>
      epc.length == RfidConfig.epcLengthBytes &&
      epcHex.toUpperCase().startsWith(RfidConfig.epcPrefixHex.toUpperCase());

  /// Check if this appears to be an unwritten/blank tag
  ///
  /// An unwritten tag will NOT have our Saturday prefix.
  /// This is used to identify tags that can be written during bulk add.
  bool get isUnwrittenTag => !isSaturdayTag;

  /// EPC length in bytes
  int get epcLength => epc.length;

  /// Signal strength as a rough percentage (0-100)
  ///
  /// RSSI typically ranges from about -80 dBm to -20 dBm
  /// This provides a rough indication for UI display.
  int get signalStrength {
    // RSSI is usually a signed byte, convert if needed
    final signedRssi = rssi > 127 ? rssi - 256 : rssi;
    // Clamp to reasonable range and convert to percentage
    const minRssi = -80;
    const maxRssi = -20;
    final clamped = signedRssi.clamp(minRssi, maxRssi);
    return ((clamped - minRssi) / (maxRssi - minRssi) * 100).round();
  }

  @override
  List<Object?> get props => [epc, rssi, pc];

  @override
  String toString() =>
      'TagPollResult(epc: $formattedEpc, rssi: $rssi, saturday: $isSaturdayTag)';
}
