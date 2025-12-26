import 'dart:math';
import 'package:equatable/equatable.dart';

/// Status values for RFID tag lifecycle
enum RfidTagStatus {
  generated, // EPC created in database, not yet written to physical tag
  written, // Successfully written to tag, not yet locked
  locked, // Written and password-locked (ready for deployment)
  failed, // Write or lock operation failed
  retired, // Tag decommissioned/removed from circulation
}

/// Extension to convert RfidTagStatus to/from string
extension RfidTagStatusExtension on RfidTagStatus {
  String get value {
    switch (this) {
      case RfidTagStatus.generated:
        return 'generated';
      case RfidTagStatus.written:
        return 'written';
      case RfidTagStatus.locked:
        return 'locked';
      case RfidTagStatus.failed:
        return 'failed';
      case RfidTagStatus.retired:
        return 'retired';
    }
  }

  static RfidTagStatus fromString(String value) {
    switch (value) {
      case 'generated':
        return RfidTagStatus.generated;
      case 'written':
        return RfidTagStatus.written;
      case 'locked':
        return RfidTagStatus.locked;
      case 'failed':
        return RfidTagStatus.failed;
      case 'retired':
        return RfidTagStatus.retired;
      default:
        throw ArgumentError('Invalid RfidTagStatus value: $value');
    }
  }
}

/// Represents a UHF RFID tag for vinyl record tracking
class RfidTag extends Equatable {
  /// Saturday Vinyl EPC prefix: "SV" in ASCII = 0x5356
  static const String epcPrefix = '5356';

  /// EPC length in hex characters (96 bits = 12 bytes = 24 hex chars)
  static const int epcHexLength = 24;

  /// Random portion length in hex characters (80 bits = 10 bytes = 20 hex chars)
  static const int randomHexLength = 20;

  final String id;
  final String epcIdentifier; // 96-bit EPC as 24 hex characters
  final String? tid; // Factory TID if captured
  final RfidTagStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? writtenAt; // When EPC was written to physical tag
  final DateTime? lockedAt; // When tag was locked
  final String? createdBy; // User ID who created the tag

  const RfidTag({
    required this.id,
    required this.epcIdentifier,
    this.tid,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.writtenAt,
    this.lockedAt,
    this.createdBy,
  });

  /// Check if this tag has the Saturday Vinyl EPC prefix (0x5356 = "SV")
  bool get isSaturdayTag =>
      epcIdentifier.toUpperCase().startsWith(epcPrefix.toUpperCase());

  /// Get EPC formatted with dashes for readability
  /// Example: 5356-A1B2-C3D4-E5F6-7890-ABCD
  String get formattedEpc {
    final upper = epcIdentifier.toUpperCase();
    if (upper.length != epcHexLength) return upper;
    return '${upper.substring(0, 4)}-${upper.substring(4, 8)}-${upper.substring(8, 12)}-${upper.substring(12, 16)}-${upper.substring(16, 20)}-${upper.substring(20, 24)}';
  }

  /// Generate a new EPC with Saturday Vinyl prefix + random 80 bits
  /// Returns 24 hex characters: "5356" + 20 random hex chars
  static String generateEpc({Random? random}) {
    final rng = random ?? Random.secure();
    final buffer = StringBuffer(epcPrefix);

    // Generate 20 random hex characters (80 bits)
    for (var i = 0; i < randomHexLength; i++) {
      buffer.write(rng.nextInt(16).toRadixString(16).toUpperCase());
    }

    return buffer.toString();
  }

  /// Validate that an EPC has the correct format
  /// Must be exactly 24 hex characters
  static bool isValidEpc(String epc) {
    if (epc.length != epcHexLength) return false;
    return RegExp(r'^[0-9A-Fa-f]{24}$').hasMatch(epc);
  }

  /// Create from JSON (Supabase response)
  factory RfidTag.fromJson(Map<String, dynamic> json) {
    return RfidTag(
      id: json['id'] as String,
      epcIdentifier: json['epc_identifier'] as String,
      tid: json['tid'] as String?,
      status: RfidTagStatusExtension.fromString(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      writtenAt: json['written_at'] != null
          ? DateTime.parse(json['written_at'] as String)
          : null,
      lockedAt: json['locked_at'] != null
          ? DateTime.parse(json['locked_at'] as String)
          : null,
      createdBy: json['created_by'] as String?,
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'epc_identifier': epcIdentifier,
      'tid': tid,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'written_at': writtenAt?.toIso8601String(),
      'locked_at': lockedAt?.toIso8601String(),
      'created_by': createdBy,
    };
  }

  /// Convert to JSON for insert (excludes id, timestamps auto-generated)
  Map<String, dynamic> toInsertJson() {
    return {
      'epc_identifier': epcIdentifier,
      'tid': tid,
      'status': status.value,
      'created_by': createdBy,
    };
  }

  /// Copy with method for immutability
  RfidTag copyWith({
    String? id,
    String? epcIdentifier,
    String? tid,
    RfidTagStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? writtenAt,
    DateTime? lockedAt,
    String? createdBy,
  }) {
    return RfidTag(
      id: id ?? this.id,
      epcIdentifier: epcIdentifier ?? this.epcIdentifier,
      tid: tid ?? this.tid,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      writtenAt: writtenAt ?? this.writtenAt,
      lockedAt: lockedAt ?? this.lockedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        epcIdentifier,
        tid,
        status,
        createdAt,
        updatedAt,
        writtenAt,
        lockedAt,
        createdBy,
      ];

  @override
  String toString() {
    return 'RfidTag(id: $id, epc: $formattedEpc, status: ${status.value})';
  }
}
