import 'package:equatable/equatable.dart';

/// Status of a tag in the system.
enum TagStatus {
  active,
  retired;

  static TagStatus fromString(String value) {
    return TagStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TagStatus.active,
    );
  }
}

/// Represents an RFID tag associated with an album.
///
/// Tags link EPC identifiers to library albums, enabling
/// automatic detection of records on devices.
class Tag extends Equatable {
  final String id;

  /// The 24-character hex EPC identifier.
  final String epcIdentifier;

  /// The library album this tag is associated with, or null if unassociated.
  final String? libraryAlbumId;

  final TagStatus status;
  final DateTime? associatedAt;
  final String? associatedBy;
  final DateTime createdAt;
  final DateTime? lastSeenAt;

  const Tag({
    required this.id,
    required this.epcIdentifier,
    this.libraryAlbumId,
    this.status = TagStatus.active,
    this.associatedAt,
    this.associatedBy,
    required this.createdAt,
    this.lastSeenAt,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      epcIdentifier: json['epc_identifier'] as String,
      libraryAlbumId: json['library_album_id'] as String?,
      status: TagStatus.fromString(json['status'] as String? ?? 'active'),
      associatedAt: json['associated_at'] != null
          ? DateTime.parse(json['associated_at'] as String)
          : null,
      associatedBy: json['associated_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'epc_identifier': epcIdentifier,
      'library_album_id': libraryAlbumId,
      'status': status.name,
      'associated_at': associatedAt?.toIso8601String(),
      'associated_by': associatedBy,
      'created_at': createdAt.toIso8601String(),
      'last_seen_at': lastSeenAt?.toIso8601String(),
    };
  }

  Tag copyWith({
    String? id,
    String? epcIdentifier,
    String? libraryAlbumId,
    TagStatus? status,
    DateTime? associatedAt,
    String? associatedBy,
    DateTime? createdAt,
    DateTime? lastSeenAt,
  }) {
    return Tag(
      id: id ?? this.id,
      epcIdentifier: epcIdentifier ?? this.epcIdentifier,
      libraryAlbumId: libraryAlbumId ?? this.libraryAlbumId,
      status: status ?? this.status,
      associatedAt: associatedAt ?? this.associatedAt,
      associatedBy: associatedBy ?? this.associatedBy,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  /// Whether this tag is currently associated with an album.
  bool get isAssociated => libraryAlbumId != null;

  /// Whether this tag is active and can be used.
  bool get isActive => status == TagStatus.active;

  @override
  List<Object?> get props => [
        id,
        epcIdentifier,
        libraryAlbumId,
        status,
        associatedAt,
        associatedBy,
        createdAt,
        lastSeenAt,
      ];
}
