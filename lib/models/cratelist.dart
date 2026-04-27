import 'package:equatable/equatable.dart';

/// Provenance of a cratelist.
///
/// `manual` is the only source supported in v1; `smart` (rule-based) and
/// `saturday` (recommended by the system) are placeholders for future work
/// and arrive via the same table so the UI can render them uniformly.
enum CratelistSource {
  manual,
  smart,
  saturday;

  static CratelistSource fromString(String value) {
    return CratelistSource.values.firstWhere(
      (s) => s.name == value,
      orElse: () => CratelistSource.manual,
    );
  }
}

/// A user-curated, ordered grouping of albums that can span libraries.
class Cratelist extends Equatable {
  final String id;
  final String name;
  final String? description;
  final String createdBy;
  final CratelistSource source;
  final Map<String, dynamic>? rules;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Cratelist({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    this.source = CratelistSource.manual,
    this.rules,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Cratelist.fromJson(Map<String, dynamic> json) {
    return Cratelist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdBy: json['created_by'] as String,
      source: CratelistSource.fromString(json['source'] as String? ?? 'manual'),
      rules: json['rules'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'created_by': createdBy,
      'source': source.name,
      'rules': rules,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Cratelist copyWith({
    String? id,
    String? name,
    String? description,
    String? createdBy,
    CratelistSource? source,
    Map<String, dynamic>? rules,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Cratelist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      source: source ?? this.source,
      rules: rules ?? this.rules,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        createdBy,
        source,
        rules,
        createdAt,
        updatedAt,
      ];
}
