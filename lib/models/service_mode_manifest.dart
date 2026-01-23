import 'package:equatable/equatable.dart';

/// Device capabilities as reported in the Service Mode Manifest
class DeviceCapabilities extends Equatable {
  final bool wifi;
  final bool bluetooth;
  final bool thread; // Thread Device (joins existing network)
  final bool threadBr; // Thread Border Router (creates network, provides credentials)
  final bool cloud;
  final bool rfid;
  final bool audio;
  final bool display;
  final bool battery;
  final bool button;

  const DeviceCapabilities({
    this.wifi = false,
    this.bluetooth = false,
    this.thread = false,
    this.threadBr = false,
    this.cloud = false,
    this.rfid = false,
    this.audio = false,
    this.display = false,
    this.battery = false,
    this.button = false,
  });

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    return DeviceCapabilities(
      wifi: json['wifi'] as bool? ?? false,
      bluetooth: json['bluetooth'] as bool? ?? false,
      thread: json['thread'] as bool? ?? false,
      threadBr: json['thread_br'] as bool? ?? false,
      cloud: json['cloud'] as bool? ?? false,
      rfid: json['rfid'] as bool? ?? false,
      audio: json['audio'] as bool? ?? false,
      display: json['display'] as bool? ?? false,
      battery: json['battery'] as bool? ?? false,
      button: json['button'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wifi': wifi,
      'bluetooth': bluetooth,
      'thread': thread,
      'thread_br': threadBr,
      'cloud': cloud,
      'rfid': rfid,
      'audio': audio,
      'display': display,
      'battery': battery,
      'button': button,
    };
  }

  /// Get list of enabled capabilities
  List<String> get enabledCapabilities {
    final enabled = <String>[];
    if (wifi) enabled.add('wifi');
    if (bluetooth) enabled.add('bluetooth');
    if (thread) enabled.add('thread');
    if (threadBr) enabled.add('thread_br');
    if (cloud) enabled.add('cloud');
    if (rfid) enabled.add('rfid');
    if (audio) enabled.add('audio');
    if (display) enabled.add('display');
    if (battery) enabled.add('battery');
    if (button) enabled.add('button');
    return enabled;
  }

  @override
  List<Object?> get props => [
        wifi,
        bluetooth,
        thread,
        threadBr,
        cloud,
        rfid,
        audio,
        display,
        battery,
        button,
      ];
}

/// Provisioning field requirements from manifest
class ProvisioningFields extends Equatable {
  final List<String> required;
  final List<String> optional;

  const ProvisioningFields({
    this.required = const [],
    this.optional = const [],
  });

  factory ProvisioningFields.fromJson(Map<String, dynamic> json) {
    return ProvisioningFields(
      required: (json['required'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      optional: (json['optional'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'required': required,
      'optional': optional,
    };
  }

  /// Get all fields (required + optional)
  List<String> get allFields => [...required, ...optional];

  @override
  List<Object?> get props => [required, optional];
}

/// Custom command parameter definition
class CommandParameter extends Equatable {
  final String type;
  final bool required;
  final dynamic min;
  final dynamic max;
  final String? description;

  const CommandParameter({
    required this.type,
    this.required = false,
    this.min,
    this.max,
    this.description,
  });

  factory CommandParameter.fromJson(Map<String, dynamic> json) {
    return CommandParameter(
      type: json['type'] as String? ?? 'string',
      required: json['required'] as bool? ?? false,
      min: json['min'],
      max: json['max'],
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'required': required,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (description != null) 'description': description,
    };
  }

  @override
  List<Object?> get props => [type, required, min, max, description];
}

/// Custom command definition from manifest
class CustomCommand extends Equatable {
  final String name;
  final String description;
  final Map<String, CommandParameter> parameters;

  const CustomCommand({
    required this.name,
    required this.description,
    this.parameters = const {},
  });

  factory CustomCommand.fromJson(Map<String, dynamic> json) {
    final paramsJson = json['parameters'] as Map<String, dynamic>? ?? {};
    final parameters = <String, CommandParameter>{};
    for (final entry in paramsJson.entries) {
      if (entry.value is Map<String, dynamic>) {
        parameters[entry.key] =
            CommandParameter.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    return CustomCommand(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      parameters: parameters,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'parameters':
          parameters.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  @override
  List<Object?> get props => [name, description, parameters];
}

/// LED pattern definition
class LedPattern extends Equatable {
  final String color;
  final String pattern;

  const LedPattern({
    required this.color,
    required this.pattern,
  });

  factory LedPattern.fromJson(Map<String, dynamic> json) {
    return LedPattern(
      color: json['color'] as String? ?? 'white',
      pattern: json['pattern'] as String? ?? 'solid',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'color': color,
      'pattern': pattern,
    };
  }

  @override
  List<Object?> get props => [color, pattern];
}

/// Service Mode Manifest - describes device capabilities and configuration
/// Retrieved from device via get_manifest command, embedded in firmware
class ServiceModeManifest extends Equatable {
  final String manifestVersion;
  final String deviceType;
  final String deviceName;
  final String? firmwareId; // UUID linking to firmware_versions table
  final String firmwareVersion;
  final DeviceCapabilities capabilities;
  final ProvisioningFields provisioningFields;
  final List<String> supportedTests;
  final List<String> statusFields;
  final List<CustomCommand> customCommands;
  final Map<String, LedPattern> ledPatterns;

  const ServiceModeManifest({
    required this.manifestVersion,
    required this.deviceType,
    required this.deviceName,
    this.firmwareId,
    required this.firmwareVersion,
    required this.capabilities,
    required this.provisioningFields,
    this.supportedTests = const [],
    this.statusFields = const [],
    this.customCommands = const [],
    this.ledPatterns = const {},
  });

  /// Create from device JSON response (data field from get_manifest)
  factory ServiceModeManifest.fromDeviceJson(Map<String, dynamic> json) {
    // Parse custom commands
    final customCommandsJson = json['custom_commands'] as List<dynamic>? ?? [];
    final customCommands = customCommandsJson
        .whereType<Map<String, dynamic>>()
        .map((e) => CustomCommand.fromJson(e))
        .toList();

    // Parse LED patterns
    final ledPatternsJson = json['led_patterns'] as Map<String, dynamic>? ?? {};
    final ledPatterns = <String, LedPattern>{};
    for (final entry in ledPatternsJson.entries) {
      if (entry.value is Map<String, dynamic>) {
        ledPatterns[entry.key] =
            LedPattern.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    return ServiceModeManifest(
      manifestVersion: json['manifest_version'] as String? ?? '1.0',
      deviceType: json['device_type'] as String? ?? 'unknown',
      deviceName: json['device_name'] as String? ?? 'Unknown Device',
      firmwareId: json['firmware_id'] as String?,
      firmwareVersion: json['firmware_version'] as String? ?? '0.0.0',
      capabilities: json['capabilities'] != null
          ? DeviceCapabilities.fromJson(
              json['capabilities'] as Map<String, dynamic>)
          : const DeviceCapabilities(),
      provisioningFields: json['provisioning_fields'] != null
          ? ProvisioningFields.fromJson(
              json['provisioning_fields'] as Map<String, dynamic>)
          : const ProvisioningFields(),
      supportedTests: (json['supported_tests'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      statusFields: (json['status_fields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      customCommands: customCommands,
      ledPatterns: ledPatterns,
    );
  }

  /// Convert to JSON for embedding in firmware (developer tool)
  Map<String, dynamic> toJson() {
    return {
      'manifest_version': manifestVersion,
      'device_type': deviceType,
      'device_name': deviceName,
      if (firmwareId != null) 'firmware_id': firmwareId,
      'firmware_version': firmwareVersion,
      'capabilities': capabilities.toJson(),
      'provisioning_fields': provisioningFields.toJson(),
      'supported_tests': supportedTests,
      'status_fields': statusFields,
      'custom_commands': customCommands.map((e) => e.toJson()).toList(),
      'led_patterns':
          ledPatterns.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  /// Check if a specific test is supported
  bool supportsTest(String testName) => supportedTests.contains(testName);

  /// Check if a specific capability is enabled
  bool hasCapability(String capability) {
    switch (capability) {
      case 'wifi':
        return capabilities.wifi;
      case 'bluetooth':
        return capabilities.bluetooth;
      case 'thread':
        return capabilities.thread;
      case 'thread_br':
        return capabilities.threadBr;
      case 'cloud':
        return capabilities.cloud;
      case 'rfid':
        return capabilities.rfid;
      case 'audio':
        return capabilities.audio;
      case 'display':
        return capabilities.display;
      case 'battery':
        return capabilities.battery;
      case 'button':
        return capabilities.button;
      default:
        return false;
    }
  }

  /// Create empty manifest for initialization
  factory ServiceModeManifest.empty() {
    return const ServiceModeManifest(
      manifestVersion: '1.0',
      deviceType: '',
      deviceName: '',
      firmwareVersion: '',
      capabilities: DeviceCapabilities(),
      provisioningFields: ProvisioningFields(),
    );
  }

  ServiceModeManifest copyWith({
    String? manifestVersion,
    String? deviceType,
    String? deviceName,
    String? firmwareId,
    String? firmwareVersion,
    DeviceCapabilities? capabilities,
    ProvisioningFields? provisioningFields,
    List<String>? supportedTests,
    List<String>? statusFields,
    List<CustomCommand>? customCommands,
    Map<String, LedPattern>? ledPatterns,
  }) {
    return ServiceModeManifest(
      manifestVersion: manifestVersion ?? this.manifestVersion,
      deviceType: deviceType ?? this.deviceType,
      deviceName: deviceName ?? this.deviceName,
      firmwareId: firmwareId ?? this.firmwareId,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      capabilities: capabilities ?? this.capabilities,
      provisioningFields: provisioningFields ?? this.provisioningFields,
      supportedTests: supportedTests ?? this.supportedTests,
      statusFields: statusFields ?? this.statusFields,
      customCommands: customCommands ?? this.customCommands,
      ledPatterns: ledPatterns ?? this.ledPatterns,
    );
  }

  @override
  List<Object?> get props => [
        manifestVersion,
        deviceType,
        deviceName,
        firmwareId,
        firmwareVersion,
        capabilities,
        provisioningFields,
        supportedTests,
        statusFields,
        customCommands,
        ledPatterns,
      ];

  @override
  String toString() =>
      'ServiceModeManifest(deviceType: $deviceType, firmwareVersion: $firmwareVersion)';
}
