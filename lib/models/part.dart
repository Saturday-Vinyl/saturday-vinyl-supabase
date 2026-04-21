import 'package:equatable/equatable.dart';

/// Type of part in the inventory system
enum PartType {
  rawMaterial,
  component,
  subAssembly,
  pcbBlank;

  String get value {
    switch (this) {
      case PartType.rawMaterial:
        return 'raw_material';
      case PartType.component:
        return 'component';
      case PartType.subAssembly:
        return 'sub_assembly';
      case PartType.pcbBlank:
        return 'pcb_blank';
    }
  }

  String get displayName {
    switch (this) {
      case PartType.rawMaterial:
        return 'Raw Material';
      case PartType.component:
        return 'Component';
      case PartType.subAssembly:
        return 'Sub-Assembly';
      case PartType.pcbBlank:
        return 'PCB Blank';
    }
  }

  static PartType fromString(String value) {
    switch (value) {
      case 'raw_material':
        return PartType.rawMaterial;
      case 'component':
        return PartType.component;
      case 'sub_assembly':
        return PartType.subAssembly;
      case 'pcb_blank':
        return PartType.pcbBlank;
      default:
        return PartType.rawMaterial;
    }
  }
}

/// Category of part
enum PartCategory {
  wood,
  electronics,
  hardware,
  fastener,
  battery,
  packaging,
  other;

  String get value => name;

  String get displayName {
    switch (this) {
      case PartCategory.wood:
        return 'Wood';
      case PartCategory.electronics:
        return 'Electronics';
      case PartCategory.hardware:
        return 'Hardware';
      case PartCategory.fastener:
        return 'Fastener';
      case PartCategory.battery:
        return 'Battery';
      case PartCategory.packaging:
        return 'Packaging';
      case PartCategory.other:
        return 'Other';
    }
  }

  static PartCategory fromString(String value) {
    return PartCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PartCategory.other,
    );
  }
}

/// Unit of measure for parts
enum UnitOfMeasure {
  each,
  boardFeet,
  linearFeet,
  meters,
  inches,
  squareFeet,
  grams,
  milliliters;

  String get value {
    switch (this) {
      case UnitOfMeasure.each:
        return 'each';
      case UnitOfMeasure.boardFeet:
        return 'board_feet';
      case UnitOfMeasure.linearFeet:
        return 'linear_feet';
      case UnitOfMeasure.meters:
        return 'meters';
      case UnitOfMeasure.inches:
        return 'inches';
      case UnitOfMeasure.squareFeet:
        return 'square_feet';
      case UnitOfMeasure.grams:
        return 'grams';
      case UnitOfMeasure.milliliters:
        return 'milliliters';
    }
  }

  String get displayName {
    switch (this) {
      case UnitOfMeasure.each:
        return 'ea';
      case UnitOfMeasure.boardFeet:
        return 'bd ft';
      case UnitOfMeasure.linearFeet:
        return 'lin ft';
      case UnitOfMeasure.meters:
        return 'm';
      case UnitOfMeasure.inches:
        return 'in';
      case UnitOfMeasure.squareFeet:
        return 'sq ft';
      case UnitOfMeasure.grams:
        return 'g';
      case UnitOfMeasure.milliliters:
        return 'mL';
    }
  }

  static UnitOfMeasure fromString(String value) {
    switch (value) {
      case 'each':
        return UnitOfMeasure.each;
      case 'board_feet':
        return UnitOfMeasure.boardFeet;
      case 'linear_feet':
        return UnitOfMeasure.linearFeet;
      case 'meters':
        return UnitOfMeasure.meters;
      case 'inches':
        return UnitOfMeasure.inches;
      case 'square_feet':
        return UnitOfMeasure.squareFeet;
      case 'grams':
        return UnitOfMeasure.grams;
      case 'milliliters':
        return UnitOfMeasure.milliliters;
      default:
        return UnitOfMeasure.each;
    }
  }
}

/// Part model representing a material, component, or sub-assembly used in production
class Part extends Equatable {
  final String id;
  final String name;
  final String partNumber;
  final String? description;
  final PartType partType;
  final PartCategory category;
  final UnitOfMeasure unitOfMeasure;
  final double? reorderThreshold;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Part({
    required this.id,
    required this.name,
    required this.partNumber,
    this.description,
    required this.partType,
    required this.category,
    required this.unitOfMeasure,
    this.reorderThreshold,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Part.fromJson(Map<String, dynamic> json) {
    return Part(
      id: json['id'] as String,
      name: json['name'] as String,
      partNumber: json['part_number'] as String,
      description: json['description'] as String?,
      partType: PartType.fromString(json['part_type'] as String),
      category: PartCategory.fromString(json['category'] as String),
      unitOfMeasure: UnitOfMeasure.fromString(json['unit_of_measure'] as String),
      reorderThreshold: json['reorder_threshold'] != null
          ? (json['reorder_threshold'] as num).toDouble()
          : null,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'part_number': partNumber,
      'description': description,
      'part_type': partType.value,
      'category': category.value,
      'unit_of_measure': unitOfMeasure.value,
      'reorder_threshold': reorderThreshold,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Part copyWith({
    String? id,
    String? name,
    String? partNumber,
    String? description,
    PartType? partType,
    PartCategory? category,
    UnitOfMeasure? unitOfMeasure,
    double? reorderThreshold,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Part(
      id: id ?? this.id,
      name: name ?? this.name,
      partNumber: partNumber ?? this.partNumber,
      description: description ?? this.description,
      partType: partType ?? this.partType,
      category: category ?? this.category,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      reorderThreshold: reorderThreshold ?? this.reorderThreshold,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        partNumber,
        description,
        partType,
        category,
        unitOfMeasure,
        reorderThreshold,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'Part(id: $id, name: $name, partNumber: $partNumber, type: ${partType.displayName})';
  }
}
