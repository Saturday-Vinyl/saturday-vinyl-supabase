import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/step_type.dart';
import 'package:saturday_app/models/step_gcode_file.dart';

/// ProductionStep model representing a step in the production workflow for a product
/// Note: Provisioning manifests are now embedded in the firmware binary
/// and retrieved via the get_manifest command in Service Mode.
class ProductionStep extends Equatable {
  final String id; // UUID
  final String productId; // Foreign key to Product
  final String name;
  final String? description;
  final int stepOrder; // Order in which steps should be completed
  final String? fileUrl; // URL to production file (gcode, design file, etc.)
  final String? fileName; // Original filename
  final String? fileType; // File extension/type (e.g., "gcode", "svg")

  // Step type and machine integration
  final StepType stepType; // Type of step (general, cnc_milling, laser_cutting)

  // QR engraving parameters (for laser cutting steps)
  final bool engraveQr; // Whether to engrave the unit QR code
  final double? qrXOffset; // X-axis offset for QR code (mm)
  final double? qrYOffset; // Y-axis offset for QR code (mm)
  final double? qrSize; // Size of QR code (mm)
  final int? qrPowerPercent; // Laser power percentage (0-100)
  final int? qrSpeedMmMin; // Laser speed (mm/min)

  // Firmware provisioning parameters
  final String? firmwareVersionId; // FK to firmware_versions (specifies which firmware to flash)

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Optional: List of gCode files associated with this step (populated via join)
  final List<StepGCodeFile>? gcodeFiles;

  const ProductionStep({
    required this.id,
    required this.productId,
    required this.name,
    this.description,
    required this.stepOrder,
    this.fileUrl,
    this.fileName,
    this.fileType,
    this.stepType = StepType.general,
    this.engraveQr = false,
    this.qrXOffset,
    this.qrYOffset,
    this.qrSize,
    this.qrPowerPercent,
    this.qrSpeedMmMin,
    this.firmwareVersionId,
    required this.createdAt,
    required this.updatedAt,
    this.gcodeFiles,
  });

  /// Validate that the production step is valid
  bool isValid() {
    // Step order must be positive
    if (stepOrder <= 0) {
      return false;
    }

    // Name is required
    if (name.isEmpty) {
      return false;
    }

    // Validate QR parameters if QR engraving is enabled
    if (engraveQr) {
      if (qrXOffset == null || qrYOffset == null || qrSize == null) {
        return false;
      }
      if (qrPowerPercent == null || qrPowerPercent! < 0 || qrPowerPercent! > 100) {
        return false;
      }
      if (qrSpeedMmMin == null || qrSpeedMmMin! <= 0) {
        return false;
      }
      if (qrSize! <= 0) {
        return false;
      }
    }

    return true;
  }

  /// Check if this is a firmware provisioning step
  bool get isFirmwareProvisioningStep => stepType.isFirmwareProvisioning;

  /// Create ProductionStep from JSON
  factory ProductionStep.fromJson(Map<String, dynamic> json) {
    // Parse gCode files if present (from join)
    List<StepGCodeFile>? gcodeFiles;
    if (json['step_gcode_files'] != null) {
      gcodeFiles = (json['step_gcode_files'] as List)
          .map((item) => StepGCodeFile.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return ProductionStep(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      stepOrder: json['step_order'] as int,
      fileUrl: json['file_url'] as String?,
      fileName: json['file_name'] as String?,
      fileType: json['file_type'] as String?,
      stepType: json['step_type'] != null
          ? StepType.fromString(json['step_type'] as String)
          : StepType.general,
      engraveQr: json['engrave_qr'] as bool? ?? false,
      qrXOffset: json['qr_x_offset'] != null
          ? (json['qr_x_offset'] as num).toDouble()
          : null,
      qrYOffset: json['qr_y_offset'] != null
          ? (json['qr_y_offset'] as num).toDouble()
          : null,
      qrSize: json['qr_size'] != null
          ? (json['qr_size'] as num).toDouble()
          : null,
      qrPowerPercent: json['qr_power_percent'] as int?,
      qrSpeedMmMin: json['qr_speed_mm_min'] as int?,
      firmwareVersionId: json['firmware_version_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      gcodeFiles: gcodeFiles,
    );
  }

  /// Convert ProductionStep to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'name': name,
      'description': description,
      'step_order': stepOrder,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_type': fileType,
      'step_type': stepType.value,
      'engrave_qr': engraveQr,
      'qr_x_offset': qrXOffset,
      'qr_y_offset': qrYOffset,
      'qr_size': qrSize,
      'qr_power_percent': qrPowerPercent,
      'qr_speed_mm_min': qrSpeedMmMin,
      'firmware_version_id': firmwareVersionId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of ProductionStep with updated fields
  ProductionStep copyWith({
    String? id,
    String? productId,
    String? name,
    String? description,
    int? stepOrder,
    String? fileUrl,
    String? fileName,
    String? fileType,
    StepType? stepType,
    bool? engraveQr,
    double? qrXOffset,
    double? qrYOffset,
    double? qrSize,
    int? qrPowerPercent,
    int? qrSpeedMmMin,
    String? firmwareVersionId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<StepGCodeFile>? gcodeFiles,
  }) {
    return ProductionStep(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      description: description ?? this.description,
      stepOrder: stepOrder ?? this.stepOrder,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileType: fileType ?? this.fileType,
      stepType: stepType ?? this.stepType,
      engraveQr: engraveQr ?? this.engraveQr,
      qrXOffset: qrXOffset ?? this.qrXOffset,
      qrYOffset: qrYOffset ?? this.qrYOffset,
      qrSize: qrSize ?? this.qrSize,
      qrPowerPercent: qrPowerPercent ?? this.qrPowerPercent,
      qrSpeedMmMin: qrSpeedMmMin ?? this.qrSpeedMmMin,
      firmwareVersionId: firmwareVersionId ?? this.firmwareVersionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      gcodeFiles: gcodeFiles ?? this.gcodeFiles,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        name,
        description,
        stepOrder,
        fileUrl,
        fileName,
        fileType,
        stepType,
        engraveQr,
        qrXOffset,
        qrYOffset,
        qrSize,
        qrPowerPercent,
        qrSpeedMmMin,
        firmwareVersionId,
        createdAt,
        updatedAt,
        gcodeFiles,
      ];

  @override
  String toString() {
    return 'ProductionStep(id: $id, name: $name, stepOrder: $stepOrder, stepType: ${stepType.displayName})';
  }
}
