import 'package:equatable/equatable.dart';

/// Status values for RFID tag roll lifecycle
enum RfidTagRollStatus {
  writing, // Currently writing tags to the roll
  readyToPrint, // All tags written, ready for batch printing
  printing, // Currently printing labels
  completed, // All labels printed
}

/// Extension to convert RfidTagRollStatus to/from string
extension RfidTagRollStatusExtension on RfidTagRollStatus {
  String get value {
    switch (this) {
      case RfidTagRollStatus.writing:
        return 'writing';
      case RfidTagRollStatus.readyToPrint:
        return 'ready_to_print';
      case RfidTagRollStatus.printing:
        return 'printing';
      case RfidTagRollStatus.completed:
        return 'completed';
    }
  }

  static RfidTagRollStatus fromString(String value) {
    switch (value) {
      case 'writing':
        return RfidTagRollStatus.writing;
      case 'ready_to_print':
        return RfidTagRollStatus.readyToPrint;
      case 'printing':
        return RfidTagRollStatus.printing;
      case 'completed':
        return RfidTagRollStatus.completed;
      default:
        throw ArgumentError('Invalid RfidTagRollStatus value: $value');
    }
  }
}

/// Represents a roll of RFID tags for batch writing and printing
class RfidTagRoll extends Equatable {
  final String id;
  final double labelWidthMm;
  final double labelHeightMm;
  final int labelCount;
  final RfidTagRollStatus status;
  final int lastPrintedPosition;
  final String? manufacturerUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  const RfidTagRoll({
    required this.id,
    required this.labelWidthMm,
    required this.labelHeightMm,
    required this.labelCount,
    required this.status,
    required this.lastPrintedPosition,
    this.manufacturerUrl,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  /// Get a short display ID (first 8 chars of UUID)
  String get shortId => id.length >= 8 ? id.substring(0, 8) : id;

  /// Get label dimensions as formatted string
  String get dimensionsDisplay =>
      '${labelWidthMm.toStringAsFixed(1)} x ${labelHeightMm.toStringAsFixed(1)} mm';

  /// Check if roll is currently being written
  bool get isWriting => status == RfidTagRollStatus.writing;

  /// Check if roll is ready for printing
  bool get isReadyToPrint => status == RfidTagRollStatus.readyToPrint;

  /// Check if roll is currently printing
  bool get isPrinting => status == RfidTagRollStatus.printing;

  /// Check if roll printing is completed
  bool get isCompleted => status == RfidTagRollStatus.completed;

  /// Check if all labels have been printed
  bool get allLabelsPrinted => lastPrintedPosition >= labelCount;

  /// Get remaining labels to print
  int get remainingToPrint =>
      (labelCount - lastPrintedPosition).clamp(0, labelCount);

  /// Get print progress as percentage (0.0 to 1.0)
  double get printProgress =>
      labelCount > 0 ? lastPrintedPosition / labelCount : 0.0;

  /// Create from JSON (Supabase response)
  factory RfidTagRoll.fromJson(Map<String, dynamic> json) {
    return RfidTagRoll(
      id: json['id'] as String,
      labelWidthMm: (json['label_width_mm'] as num).toDouble(),
      labelHeightMm: (json['label_height_mm'] as num).toDouble(),
      labelCount: json['label_count'] as int,
      status:
          RfidTagRollStatusExtension.fromString(json['status'] as String),
      lastPrintedPosition: json['last_printed_position'] as int,
      manufacturerUrl: json['manufacturer_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdBy: json['created_by'] as String?,
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label_width_mm': labelWidthMm,
      'label_height_mm': labelHeightMm,
      'label_count': labelCount,
      'status': status.value,
      'last_printed_position': lastPrintedPosition,
      'manufacturer_url': manufacturerUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'created_by': createdBy,
    };
  }

  /// Convert to JSON for insert (excludes id, timestamps auto-generated)
  Map<String, dynamic> toInsertJson() {
    return {
      'label_width_mm': labelWidthMm,
      'label_height_mm': labelHeightMm,
      'label_count': labelCount,
      'status': status.value,
      'last_printed_position': lastPrintedPosition,
      'manufacturer_url': manufacturerUrl,
      'created_by': createdBy,
    };
  }

  /// Copy with method for immutability
  RfidTagRoll copyWith({
    String? id,
    double? labelWidthMm,
    double? labelHeightMm,
    int? labelCount,
    RfidTagRollStatus? status,
    int? lastPrintedPosition,
    String? manufacturerUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return RfidTagRoll(
      id: id ?? this.id,
      labelWidthMm: labelWidthMm ?? this.labelWidthMm,
      labelHeightMm: labelHeightMm ?? this.labelHeightMm,
      labelCount: labelCount ?? this.labelCount,
      status: status ?? this.status,
      lastPrintedPosition: lastPrintedPosition ?? this.lastPrintedPosition,
      manufacturerUrl: manufacturerUrl ?? this.manufacturerUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        labelWidthMm,
        labelHeightMm,
        labelCount,
        status,
        lastPrintedPosition,
        manufacturerUrl,
        createdAt,
        updatedAt,
        createdBy,
      ];

  @override
  String toString() {
    return 'RfidTagRoll(id: $shortId, status: ${status.value}, labels: $labelCount, printed: $lastPrintedPosition)';
  }
}
