import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/tag_filter.dart';

void main() {
  group('TagSortBy', () {
    test('has expected values', () {
      expect(TagSortBy.values.length, 3);
      expect(TagSortBy.values, contains(TagSortBy.createdAt));
      expect(TagSortBy.values, contains(TagSortBy.epcIdentifier));
      expect(TagSortBy.values, contains(TagSortBy.status));
    });
  });

  group('TagFilter', () {
    test('creates with default values', () {
      const filter = TagFilter();
      expect(filter.status, null);
      expect(filter.searchQuery, null);
      expect(filter.sortBy, TagSortBy.createdAt);
      expect(filter.sortAscending, false); // newest first
    });

    test('defaultFilter has expected values', () {
      expect(TagFilter.defaultFilter.status, null);
      expect(TagFilter.defaultFilter.searchQuery, null);
      expect(TagFilter.defaultFilter.sortBy, TagSortBy.createdAt);
      expect(TagFilter.defaultFilter.sortAscending, false);
    });

    test('creates with custom values', () {
      const filter = TagFilter(
        status: RfidTagStatus.active,
        searchQuery: '5356',
        sortBy: TagSortBy.epcIdentifier,
        sortAscending: true,
      );

      expect(filter.status, RfidTagStatus.active);
      expect(filter.searchQuery, '5356');
      expect(filter.sortBy, TagSortBy.epcIdentifier);
      expect(filter.sortAscending, true);
    });

    group('hasActiveFilters', () {
      test('returns false for default filter', () {
        expect(TagFilter.defaultFilter.hasActiveFilters, false);
      });

      test('returns true when status is set', () {
        const filter = TagFilter(status: RfidTagStatus.active);
        expect(filter.hasActiveFilters, true);
      });

      test('returns true when searchQuery is set', () {
        const filter = TagFilter(searchQuery: '5356');
        expect(filter.hasActiveFilters, true);
      });

      test('returns false when searchQuery is empty', () {
        const filter = TagFilter(searchQuery: '');
        expect(filter.hasActiveFilters, false);
      });

      test('returns true when both are set', () {
        const filter = TagFilter(
          status: RfidTagStatus.active,
          searchQuery: '5356',
        );
        expect(filter.hasActiveFilters, true);
      });
    });

    group('sortColumn', () {
      test('returns correct column for createdAt', () {
        const filter = TagFilter(sortBy: TagSortBy.createdAt);
        expect(filter.sortColumn, 'created_at');
      });

      test('returns correct column for epcIdentifier', () {
        const filter = TagFilter(sortBy: TagSortBy.epcIdentifier);
        expect(filter.sortColumn, 'epc_identifier');
      });

      test('returns correct column for status', () {
        const filter = TagFilter(sortBy: TagSortBy.status);
        expect(filter.sortColumn, 'status');
      });
    });

    group('copyWith', () {
      test('creates new instance with updated status', () {
        const original = TagFilter();
        final updated = original.copyWith(status: RfidTagStatus.active);

        expect(updated.status, RfidTagStatus.active);
        expect(updated.searchQuery, null);
        expect(updated.sortBy, TagSortBy.createdAt);
      });

      test('creates new instance with updated searchQuery', () {
        const original = TagFilter();
        final updated = original.copyWith(searchQuery: '5356');

        expect(updated.searchQuery, '5356');
        expect(updated.status, null);
      });

      test('creates new instance with updated sortBy', () {
        const original = TagFilter();
        final updated = original.copyWith(sortBy: TagSortBy.epcIdentifier);

        expect(updated.sortBy, TagSortBy.epcIdentifier);
      });

      test('creates new instance with updated sortAscending', () {
        const original = TagFilter();
        final updated = original.copyWith(sortAscending: true);

        expect(updated.sortAscending, true);
      });

      test('clearStatus sets status to null', () {
        const original = TagFilter(status: RfidTagStatus.active);
        final updated = original.copyWith(clearStatus: true);

        expect(updated.status, null);
      });

      test('clearSearch sets searchQuery to null', () {
        const original = TagFilter(searchQuery: '5356');
        final updated = original.copyWith(clearSearch: true);

        expect(updated.searchQuery, null);
      });

      test('clearStatus overrides new status value', () {
        const original = TagFilter(status: RfidTagStatus.active);
        final updated = original.copyWith(
          status: RfidTagStatus.written,
          clearStatus: true,
        );

        expect(updated.status, null);
      });

      test('preserves all values when no args', () {
        const original = TagFilter(
          status: RfidTagStatus.active,
          searchQuery: '5356',
          sortBy: TagSortBy.epcIdentifier,
          sortAscending: true,
        );
        final updated = original.copyWith();

        expect(updated, equals(original));
      });
    });

    group('equality', () {
      test('equal filters are equal', () {
        const filter1 = TagFilter(
          status: RfidTagStatus.active,
          searchQuery: '5356',
        );
        const filter2 = TagFilter(
          status: RfidTagStatus.active,
          searchQuery: '5356',
        );

        expect(filter1, equals(filter2));
        expect(filter1.hashCode, equals(filter2.hashCode));
      });

      test('different status makes filters unequal', () {
        const filter1 = TagFilter(status: RfidTagStatus.active);
        const filter2 = TagFilter(status: RfidTagStatus.written);

        expect(filter1, isNot(equals(filter2)));
      });

      test('different searchQuery makes filters unequal', () {
        const filter1 = TagFilter(searchQuery: '5356');
        const filter2 = TagFilter(searchQuery: '1234');

        expect(filter1, isNot(equals(filter2)));
      });

      test('different sortBy makes filters unequal', () {
        const filter1 = TagFilter(sortBy: TagSortBy.createdAt);
        const filter2 = TagFilter(sortBy: TagSortBy.status);

        expect(filter1, isNot(equals(filter2)));
      });

      test('different sortAscending makes filters unequal', () {
        const filter1 = TagFilter(sortAscending: true);
        const filter2 = TagFilter(sortAscending: false);

        expect(filter1, isNot(equals(filter2)));
      });
    });

    group('toString', () {
      test('includes key information', () {
        const filter = TagFilter(
          status: RfidTagStatus.active,
          searchQuery: '5356',
          sortBy: TagSortBy.createdAt,
          sortAscending: false,
        );

        final str = filter.toString();
        expect(str, contains('active'));
        expect(str, contains('5356'));
        expect(str, contains('createdAt'));
      });
    });
  });
}
