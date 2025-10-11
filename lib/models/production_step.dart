import 'package:equatable/equatable.dart';

/// ProductionStep model representing a step in the production workflow for a product
class ProductionStep extends Equatable {
  final String id; // UUID
  final String productId; // Foreign key to Product
  final String name;
  final String? description;
  final int stepOrder; // Order in which steps should be completed
  final String? fileUrl; // URL to production file (gcode, design file, etc.)
  final String? fileName; // Original filename
  final String? fileType; // File extension/type (e.g., "gcode", "svg")
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductionStep({
    required this.id,
    required this.productId,
    required this.name,
    this.description,
    required this.stepOrder,
    this.fileUrl,
    this.fileName,
    this.fileType,
    required this.createdAt,
    required this.updatedAt,
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

    return true;
  }

  /// Check if this is a firmware provisioning step
  /// Returns true if the step name or description contains "firmware"
  bool isFirmwareStep() {
    final nameLower = name.toLowerCase();
    final descLower = description?.toLowerCase() ?? '';
    return nameLower.contains('firmware') ||
           nameLower.contains('flash') && nameLower.contains('device') ||
           descLower.contains('firmware provisioning') ||
           descLower.contains('flash firmware');
  }

  /// Create ProductionStep from JSON
  factory ProductionStep.fromJson(Map<String, dynamic> json) {
    return ProductionStep(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      stepOrder: json['step_order'] as int,
      fileUrl: json['file_url'] as String?,
      fileName: json['file_name'] as String?,
      fileType: json['file_type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
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
    DateTime? createdAt,
    DateTime? updatedAt,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'ProductionStep(id: $id, name: $name, stepOrder: $stepOrder)';
  }
}
