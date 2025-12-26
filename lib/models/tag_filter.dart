import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/rfid_tag.dart';

/// Sort options for tag list
enum TagSortBy {
  createdAt,
  epcIdentifier,
  status,
}

/// Filter parameters for querying RFID tags
class TagFilter extends Equatable {
  final RfidTagStatus? status;
  final String? searchQuery;
  final TagSortBy sortBy;
  final bool sortAscending;

  const TagFilter({
    this.status,
    this.searchQuery,
    this.sortBy = TagSortBy.createdAt,
    this.sortAscending = false, // Default newest first
  });

  /// Default filter (no filters, newest first)
  static const TagFilter defaultFilter = TagFilter();

  /// Check if any filters are active
  bool get hasActiveFilters => status != null || (searchQuery?.isNotEmpty ?? false);

  /// Get the Supabase column name for sorting
  String get sortColumn {
    switch (sortBy) {
      case TagSortBy.createdAt:
        return 'created_at';
      case TagSortBy.epcIdentifier:
        return 'epc_identifier';
      case TagSortBy.status:
        return 'status';
    }
  }

  TagFilter copyWith({
    RfidTagStatus? status,
    String? searchQuery,
    TagSortBy? sortBy,
    bool? sortAscending,
    bool clearStatus = false,
    bool clearSearch = false,
  }) {
    return TagFilter(
      status: clearStatus ? null : (status ?? this.status),
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  @override
  List<Object?> get props => [status, searchQuery, sortBy, sortAscending];

  @override
  String toString() {
    return 'TagFilter(status: $status, search: $searchQuery, sortBy: $sortBy, asc: $sortAscending)';
  }
}
