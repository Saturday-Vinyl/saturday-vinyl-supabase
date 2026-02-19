import 'package:equatable/equatable.dart';

/// Represents a test definition within a capability
class CapabilityTest extends Equatable {
  final String name;
  final String displayName;
  final String? description;
  final Map<String, dynamic> parametersSchema;
  final Map<String, dynamic> resultSchema;

  /// The capability name this test belongs to (set during aggregation)
  final String? capabilityName;

  const CapabilityTest({
    required this.name,
    required this.displayName,
    this.description,
    this.parametersSchema = const {},
    this.resultSchema = const {},
    this.capabilityName,
  });

  factory CapabilityTest.fromJson(Map<String, dynamic> json) {
    return CapabilityTest(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String?,
      parametersSchema: json['parameters_schema'] != null
          ? Map<String, dynamic>.from(json['parameters_schema'] as Map)
          : {},
      resultSchema: json['result_schema'] != null
          ? Map<String, dynamic>.from(json['result_schema'] as Map)
          : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'display_name': displayName,
      'description': description,
      'parameters_schema': parametersSchema,
      'result_schema': resultSchema,
    };
  }

  CapabilityTest copyWithCapability(String capabilityName) {
    return CapabilityTest(
      name: name,
      displayName: displayName,
      description: description,
      parametersSchema: parametersSchema,
      resultSchema: resultSchema,
      capabilityName: capabilityName,
    );
  }

  @override
  List<Object?> get props =>
      [name, displayName, description, parametersSchema, resultSchema, capabilityName];
}

/// Represents a device capability with input/output schemas for provisioning phases
///
/// Capabilities define configurable features of Saturday devices.
/// Each capability specifies schemas for factory/consumer provisioning
/// (both input to device and output from device), heartbeat data, and tests.
///
/// Schema naming convention: {phase}_{direction}_schema
///   - phase: factory or consumer (provisioning phase)
///   - direction: input (sent TO device) or output (returned FROM device)
class Capability extends Equatable {
  final String id;
  final String name;
  final String displayName;
  final String? description;

  /// JSON Schema for factory provisioning input (sent TO device via UART/WebSocket).
  /// Defines what the factory provisioning app can send to the device.
  /// This data persists through consumer reset.
  final Map<String, dynamic> factoryInputSchema;

  /// JSON Schema for factory provisioning output (returned FROM device).
  /// Defines what the device reports back after factory provisioning completes.
  final Map<String, dynamic> factoryOutputSchema;

  /// JSON Schema for consumer provisioning input (sent TO device via BLE).
  /// Defines what the consumer app can send to the device.
  /// Also drives BLE service/characteristic generation in firmware.
  /// This data is wiped on consumer reset.
  final Map<String, dynamic> consumerInputSchema;

  /// JSON Schema for consumer provisioning output (returned FROM device).
  /// Defines what the device reports back after consumer provisioning completes.
  final Map<String, dynamic> consumerOutputSchema;

  /// JSON Schema for heartbeat telemetry data
  final Map<String, dynamic> heartbeatSchema;

  /// Test definitions with parameter and result schemas
  final List<CapabilityTest> tests;

  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Capability({
    required this.id,
    required this.name,
    required this.displayName,
    this.description,
    this.factoryInputSchema = const {},
    this.factoryOutputSchema = const {},
    this.consumerInputSchema = const {},
    this.consumerOutputSchema = const {},
    this.heartbeatSchema = const {},
    this.tests = const [],
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  /// Check if capability has factory input schema
  bool get hasFactoryInput => factoryInputSchema.isNotEmpty;

  /// Check if capability has factory output schema
  bool get hasFactoryOutput => factoryOutputSchema.isNotEmpty;

  /// Check if capability has consumer input schema
  bool get hasConsumerInput => consumerInputSchema.isNotEmpty;

  /// Check if capability has consumer output schema
  bool get hasConsumerOutput => consumerOutputSchema.isNotEmpty;

  /// Check if capability has heartbeat schema
  bool get hasHeartbeat => heartbeatSchema.isNotEmpty;

  /// Check if capability has tests
  bool get hasTests => tests.isNotEmpty;

  /// Get test by name
  CapabilityTest? getTest(String testName) {
    try {
      return tests.firstWhere((t) => t.name == testName);
    } catch (_) {
      return null;
    }
  }

  /// Create from JSON
  factory Capability.fromJson(Map<String, dynamic> json) {
    final testsJson = json['tests'];
    List<CapabilityTest> tests = [];

    if (testsJson != null && testsJson is List) {
      tests = testsJson
          .map((t) => CapabilityTest.fromJson(t as Map<String, dynamic>))
          .toList();
    }

    return Capability(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String?,
      factoryInputSchema: json['factory_input_schema'] != null
          ? Map<String, dynamic>.from(json['factory_input_schema'] as Map)
          : {},
      factoryOutputSchema: json['factory_output_schema'] != null
          ? Map<String, dynamic>.from(json['factory_output_schema'] as Map)
          : {},
      consumerInputSchema: json['consumer_input_schema'] != null
          ? Map<String, dynamic>.from(json['consumer_input_schema'] as Map)
          : {},
      consumerOutputSchema: json['consumer_output_schema'] != null
          ? Map<String, dynamic>.from(json['consumer_output_schema'] as Map)
          : {},
      heartbeatSchema: json['heartbeat_schema'] != null
          ? Map<String, dynamic>.from(json['heartbeat_schema'] as Map)
          : {},
      tests: tests,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'display_name': displayName,
      'description': description,
      'factory_input_schema': factoryInputSchema,
      'factory_output_schema': factoryOutputSchema,
      'consumer_input_schema': consumerInputSchema,
      'consumer_output_schema': consumerOutputSchema,
      'heartbeat_schema': heartbeatSchema,
      'tests': tests.map((t) => t.toJson()).toList(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Convert to JSON for insertion (without id, timestamps)
  Map<String, dynamic> toInsertJson() {
    return {
      'name': name,
      'display_name': displayName,
      'description': description,
      'factory_input_schema': factoryInputSchema,
      'factory_output_schema': factoryOutputSchema,
      'consumer_input_schema': consumerInputSchema,
      'consumer_output_schema': consumerOutputSchema,
      'heartbeat_schema': heartbeatSchema,
      'tests': tests.map((t) => t.toJson()).toList(),
      'is_active': isActive,
    };
  }

  /// Copy with method for immutability
  Capability copyWith({
    String? id,
    String? name,
    String? displayName,
    String? description,
    Map<String, dynamic>? factoryInputSchema,
    Map<String, dynamic>? factoryOutputSchema,
    Map<String, dynamic>? consumerInputSchema,
    Map<String, dynamic>? consumerOutputSchema,
    Map<String, dynamic>? heartbeatSchema,
    List<CapabilityTest>? tests,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Capability(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      factoryInputSchema: factoryInputSchema ?? this.factoryInputSchema,
      factoryOutputSchema: factoryOutputSchema ?? this.factoryOutputSchema,
      consumerInputSchema: consumerInputSchema ?? this.consumerInputSchema,
      consumerOutputSchema: consumerOutputSchema ?? this.consumerOutputSchema,
      heartbeatSchema: heartbeatSchema ?? this.heartbeatSchema,
      tests: tests ?? this.tests,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        displayName,
        description,
        factoryInputSchema,
        factoryOutputSchema,
        consumerInputSchema,
        consumerOutputSchema,
        heartbeatSchema,
        tests,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Capability(id: $id, name: $name, displayName: $displayName)';
}
