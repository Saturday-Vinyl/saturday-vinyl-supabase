import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Represents a machine-specific gcode macro for quick execution
class MachineMacro extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String machineType; // 'cnc' or 'laser'
  final String iconName; // Material Icon name
  final String gcodeCommands; // Multi-line gcode commands
  final int executionOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MachineMacro({
    required this.id,
    required this.name,
    this.description,
    required this.machineType,
    required this.iconName,
    required this.gcodeCommands,
    required this.executionOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Validate that the macro is properly configured
  bool isValid() {
    // Name must not be empty
    if (name.trim().isEmpty) {
      return false;
    }

    // Machine type must be valid
    if (machineType != 'cnc' && machineType != 'laser') {
      return false;
    }

    // Icon name must not be empty
    if (iconName.trim().isEmpty) {
      return false;
    }

    // Gcode commands must not be empty
    if (gcodeCommands.trim().isEmpty) {
      return false;
    }

    // Execution order must be positive
    if (executionOrder <= 0) {
      return false;
    }

    return true;
  }

  /// Convert icon name string to IconData
  /// Returns a default icon if the icon name is not found
  IconData getIconData() {
    final iconMap = <String, IconData>{
      // Power and control
      'power': Icons.power,
      'power_off': Icons.power_off,
      'power_settings_new': Icons.power_settings_new,

      // Playback
      'play_arrow': Icons.play_arrow,
      'pause': Icons.pause,
      'stop': Icons.stop,
      'stop_circle': Icons.stop_circle,

      // Tools and building
      'build': Icons.build,
      'construction': Icons.construction,
      'handyman': Icons.handyman,
      'settings': Icons.settings,
      'home': Icons.home,

      // Laser specific
      'flash_on': Icons.flash_on,
      'flash_off': Icons.flash_off,
      'flash_auto': Icons.flash_auto,
      'visibility': Icons.visibility,
      'visibility_off': Icons.visibility_off,

      // Fluid/coolant
      'opacity': Icons.opacity,
      'water_drop': Icons.water_drop,
      'air': Icons.air,
      'clear': Icons.clear,

      // Movement
      'refresh': Icons.refresh,
      'cached': Icons.cached,
      'rotate_right': Icons.rotate_right,
      'rotate_left': Icons.rotate_left,
      'sync': Icons.sync,

      // Directional
      'arrow_upward': Icons.arrow_upward,
      'arrow_downward': Icons.arrow_downward,
      'arrow_forward': Icons.arrow_forward,
      'arrow_back': Icons.arrow_back,
      'north': Icons.north,
      'south': Icons.south,
      'east': Icons.east,
      'west': Icons.west,

      // Actions
      'add': Icons.add,
      'remove': Icons.remove,
      'check': Icons.check,
      'close': Icons.close,
      'done': Icons.done,

      // Precision
      'speed': Icons.speed,
      'slow_motion_video': Icons.slow_motion_video,
      'fast_forward': Icons.fast_forward,
      'fast_rewind': Icons.fast_rewind,

      // Other
      'bolt': Icons.bolt,
      'electric_bolt': Icons.electric_bolt,
      'troubleshoot': Icons.troubleshoot,
      'category': Icons.category,
    };

    return iconMap[iconName] ?? Icons.settings;
  }

  /// Get the list of gcode command lines
  List<String> getCommandLines() {
    return gcodeCommands
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Create from JSON
  factory MachineMacro.fromJson(Map<String, dynamic> json) {
    return MachineMacro(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      machineType: json['machine_type'] as String,
      iconName: json['icon_name'] as String,
      gcodeCommands: json['gcode_commands'] as String,
      executionOrder: json['execution_order'] as int,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'machine_type': machineType,
      'icon_name': iconName,
      'gcode_commands': gcodeCommands,
      'execution_order': executionOrder,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Copy with method for immutability
  MachineMacro copyWith({
    String? id,
    String? name,
    String? description,
    String? machineType,
    String? iconName,
    String? gcodeCommands,
    int? executionOrder,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MachineMacro(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      machineType: machineType ?? this.machineType,
      iconName: iconName ?? this.iconName,
      gcodeCommands: gcodeCommands ?? this.gcodeCommands,
      executionOrder: executionOrder ?? this.executionOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        machineType,
        iconName,
        gcodeCommands,
        executionOrder,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'MachineMacro(id: $id, name: $name, machineType: $machineType, executionOrder: $executionOrder)';
  }
}
