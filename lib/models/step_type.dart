/// Enum representing the type of production step
enum StepType {
  /// General manual production step
  general('general'),

  /// CNC milling machine step
  cncMilling('cnc_milling'),

  /// Laser cutting/engraving step
  laserCutting('laser_cutting');

  const StepType(this.value);

  /// Database value for this step type
  final String value;

  /// Create StepType from database value
  static StepType fromString(String value) {
    switch (value) {
      case 'general':
        return StepType.general;
      case 'cnc_milling':
        return StepType.cncMilling;
      case 'laser_cutting':
        return StepType.laserCutting;
      default:
        throw ArgumentError('Unknown step type: $value');
    }
  }

  /// Get display name for UI
  String get displayName {
    switch (this) {
      case StepType.general:
        return 'General';
      case StepType.cncMilling:
        return 'CNC Milling';
      case StepType.laserCutting:
        return 'Laser Cutting/Engraving';
    }
  }

  /// Get machine type for gCode filtering (null for general steps)
  String? get machineType {
    switch (this) {
      case StepType.general:
        return null;
      case StepType.cncMilling:
        return 'cnc';
      case StepType.laserCutting:
        return 'laser';
    }
  }

  /// Check if this step type uses machine control
  bool get requiresMachine {
    return this != StepType.general;
  }

  /// Check if this is a CNC step
  bool get isCnc {
    return this == StepType.cncMilling;
  }

  /// Check if this is a Laser step
  bool get isLaser {
    return this == StepType.laserCutting;
  }
}
