import 'package:equatable/equatable.dart';

/// Represents a command definition within a capability
///
/// Commands are flat top-level operations dispatched by name (e.g., "connect", "scan").
/// See Device Command Protocol v1.3.0.
class CapabilityCommand extends Equatable {
  final String name;
  final String displayName;
  final String? description;
  final Map<String, dynamic> parametersSchema;
  final Map<String, dynamic> resultSchema;

  /// The capability name this command belongs to (set during aggregation)
  final String? capabilityName;

  const CapabilityCommand({
    required this.name,
    required this.displayName,
    this.description,
    this.parametersSchema = const {},
    this.resultSchema = const {},
    this.capabilityName,
  });

  factory CapabilityCommand.fromJson(Map<String, dynamic> json) {
    return CapabilityCommand(
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

  CapabilityCommand copyWithCapability(String capabilityName) {
    return CapabilityCommand(
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
/// (both input to device and output from device), heartbeat data, and commands.
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

  /// Command definitions with parameter and result schemas.
  /// Note: DB column is still named 'tests' pending migration.
  final List<CapabilityCommand> commands;

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
    this.commands = const [],
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

  /// Check if capability has commands
  bool get hasCommands => commands.isNotEmpty;

  /// Get command by name
  CapabilityCommand? getCommand(String commandName) {
    try {
      return commands.firstWhere((c) => c.name == commandName);
    } catch (_) {
      return null;
    }
  }

  /// Create from JSON
  factory Capability.fromJson(Map<String, dynamic> json) {
    // DB column is still named 'tests' pending migration
    final commandsJson = json['tests'];
    List<CapabilityCommand> commands = [];

    if (commandsJson != null && commandsJson is List) {
      commands = commandsJson
          .map((c) => CapabilityCommand.fromJson(c as Map<String, dynamic>))
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
      commands: commands,
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
      // DB column is still named 'tests' pending migration
      'tests': commands.map((c) => c.toJson()).toList(),
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
      // DB column is still named 'tests' pending migration
      'tests': commands.map((c) => c.toJson()).toList(),
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
    List<CapabilityCommand>? commands,
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
      commands: commands ?? this.commands,
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
        commands,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Capability(id: $id, name: $name, displayName: $displayName)';
}
