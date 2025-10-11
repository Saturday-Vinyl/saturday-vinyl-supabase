import 'package:equatable/equatable.dart';

/// Records a firmware installation on a production unit
class UnitFirmwareHistory extends Equatable {
  final String id;
  final String unitId;
  final String deviceTypeId;
  final String firmwareVersionId;
  final DateTime installedAt;
  final String installedBy;
  final String? installationMethod; // e.g., 'manual', 'esptool', 'usb-flash'
  final String? notes;

  const UnitFirmwareHistory({
    required this.id,
    required this.unitId,
    required this.deviceTypeId,
    required this.firmwareVersionId,
    required this.installedAt,
    required this.installedBy,
    this.installationMethod,
    this.notes,
  });

  /// Create UnitFirmwareHistory from JSON
  factory UnitFirmwareHistory.fromJson(Map<String, dynamic> json) {
    return UnitFirmwareHistory(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      deviceTypeId: json['device_type_id'] as String,
      firmwareVersionId: json['firmware_version_id'] as String,
      installedAt: DateTime.parse(json['installed_at'] as String),
      installedBy: json['installed_by'] as String,
      installationMethod: json['installation_method'] as String?,
      notes: json['notes'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unit_id': unitId,
      'device_type_id': deviceTypeId,
      'firmware_version_id': firmwareVersionId,
      'installed_at': installedAt.toIso8601String(),
      'installed_by': installedBy,
      'installation_method': installationMethod,
      'notes': notes,
    };
  }

  /// Convert to JSON for insertion (without id)
  Map<String, dynamic> toInsertJson() {
    return {
      'unit_id': unitId,
      'device_type_id': deviceTypeId,
      'firmware_version_id': firmwareVersionId,
      'installed_by': installedBy,
      'installation_method': installationMethod,
      'notes': notes,
    };
  }

  /// Create a copy with modified fields
  UnitFirmwareHistory copyWith({
    String? id,
    String? unitId,
    String? deviceTypeId,
    String? firmwareVersionId,
    DateTime? installedAt,
    String? installedBy,
    String? installationMethod,
    String? notes,
  }) {
    return UnitFirmwareHistory(
      id: id ?? this.id,
      unitId: unitId ?? this.unitId,
      deviceTypeId: deviceTypeId ?? this.deviceTypeId,
      firmwareVersionId: firmwareVersionId ?? this.firmwareVersionId,
      installedAt: installedAt ?? this.installedAt,
      installedBy: installedBy ?? this.installedBy,
      installationMethod: installationMethod ?? this.installationMethod,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id,
        unitId,
        deviceTypeId,
        firmwareVersionId,
        installedAt,
        installedBy,
        installationMethod,
        notes,
      ];

  @override
  String toString() => 'UnitFirmwareHistory(id: $id, unitId: $unitId, '
      'firmwareVersionId: $firmwareVersionId, installedAt: $installedAt)';
}
