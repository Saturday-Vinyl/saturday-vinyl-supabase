import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/unit.dart';

/// Sort options for unit list
enum UnitSortBy {
  createdAt,
  lastSeenAt,
  serialNumber,
  status,
}

/// Extension to get database column name for sorting
extension UnitSortByExtension on UnitSortBy {
  /// Get the database column name for this sort option
  String get columnName {
    switch (this) {
      case UnitSortBy.createdAt:
        return 'created_at';
      case UnitSortBy.lastSeenAt:
        return 'last_seen_at';
      case UnitSortBy.serialNumber:
        return 'serial_number';
      case UnitSortBy.status:
        return 'status';
    }
  }

  /// Get display name for this sort option
  String get displayName {
    switch (this) {
      case UnitSortBy.createdAt:
        return 'Created';
      case UnitSortBy.lastSeenAt:
        return 'Last Seen';
      case UnitSortBy.serialNumber:
        return 'Serial Number';
      case UnitSortBy.status:
        return 'Status';
    }
  }
}

/// Filter parameters for querying units in the dashboard
class UnitFilter extends Equatable {
  /// Filter by unit status
  final UnitStatus? status;

  /// Search query (matches serial_number and device_name)
  final String? searchQuery;

  /// Filter by online status (true = online only, false = offline only, null = all)
  final bool? isOnline;

  /// Sort field
  final UnitSortBy sortBy;

  /// Sort direction (true = ascending, false = descending)
  final bool sortAscending;

  const UnitFilter({
    this.status,
    this.searchQuery,
    this.isOnline,
    this.sortBy = UnitSortBy.createdAt,
    this.sortAscending = false, // Default: newest first
  });

  /// Default filter (no filters, newest first)
  static const UnitFilter defaultFilter = UnitFilter();

  /// Check if any filters are active
  bool get hasActiveFilters =>
      status != null ||
      (searchQuery?.isNotEmpty ?? false) ||
      isOnline != null;

  /// Get the number of active filters
  int get activeFilterCount {
    int count = 0;
    if (status != null) count++;
    if (searchQuery?.isNotEmpty ?? false) count++;
    if (isOnline != null) count++;
    return count;
  }

  /// Create a copy with updated fields
  UnitFilter copyWith({
    UnitStatus? status,
    String? searchQuery,
    bool? isOnline,
    UnitSortBy? sortBy,
    bool? sortAscending,
    bool clearStatus = false,
    bool clearSearch = false,
    bool clearOnline = false,
  }) {
    return UnitFilter(
      status: clearStatus ? null : (status ?? this.status),
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
      isOnline: clearOnline ? null : (isOnline ?? this.isOnline),
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  /// Reset all filters to default
  UnitFilter reset() => defaultFilter;

  @override
  List<Object?> get props => [
        status,
        searchQuery,
        isOnline,
        sortBy,
        sortAscending,
      ];

  @override
  String toString() {
    return 'UnitFilter(status: $status, search: $searchQuery, online: $isOnline, sortBy: $sortBy, asc: $sortAscending)';
  }
}
