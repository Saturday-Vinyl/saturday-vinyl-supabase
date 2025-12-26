import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/tag_filter.dart';
import 'package:saturday_app/providers/rfid_tag_provider.dart';

void main() {
  group('TagFilterNotifier', () {
    late TagFilterNotifier notifier;

    setUp(() {
      notifier = TagFilterNotifier();
    });

    test('initial state is default filter', () {
      expect(notifier.state, TagFilter.defaultFilter);
    });

    test('setStatus updates status', () {
      notifier.setStatus(RfidTagStatus.locked);
      expect(notifier.state.status, RfidTagStatus.locked);
    });

    test('setStatus with null clears status', () {
      notifier.setStatus(RfidTagStatus.locked);
      notifier.setStatus(null);
      expect(notifier.state.status, null);
    });

    test('setSearchQuery updates search query', () {
      notifier.setSearchQuery('5356');
      expect(notifier.state.searchQuery, '5356');
    });

    test('setSearchQuery with null clears search', () {
      notifier.setSearchQuery('5356');
      notifier.setSearchQuery(null);
      expect(notifier.state.searchQuery, null);
    });

    test('setSearchQuery with empty string clears search', () {
      notifier.setSearchQuery('5356');
      notifier.setSearchQuery('');
      expect(notifier.state.searchQuery, null);
    });

    test('setSortBy updates sort by', () {
      notifier.setSortBy(TagSortBy.epcIdentifier);
      expect(notifier.state.sortBy, TagSortBy.epcIdentifier);
    });

    test('setSortAscending updates sort ascending', () {
      notifier.setSortAscending(true);
      expect(notifier.state.sortAscending, true);
    });

    test('reset returns to default filter', () {
      notifier.setStatus(RfidTagStatus.locked);
      notifier.setSearchQuery('5356');
      notifier.setSortBy(TagSortBy.epcIdentifier);
      notifier.setSortAscending(true);

      notifier.reset();

      expect(notifier.state, TagFilter.defaultFilter);
    });

    test('multiple updates preserve other values', () {
      notifier.setStatus(RfidTagStatus.locked);
      notifier.setSearchQuery('5356');

      expect(notifier.state.status, RfidTagStatus.locked);
      expect(notifier.state.searchQuery, '5356');
    });

    test('state changes are independent', () {
      notifier.setStatus(RfidTagStatus.locked);
      final stateAfterStatus = notifier.state;

      notifier.setSearchQuery('5356');
      final stateAfterSearch = notifier.state;

      expect(stateAfterStatus.status, RfidTagStatus.locked);
      expect(stateAfterStatus.searchQuery, null);

      expect(stateAfterSearch.status, RfidTagStatus.locked);
      expect(stateAfterSearch.searchQuery, '5356');
    });
  });

  group('Provider definitions', () {
    test('rfidTagRepositoryProvider is defined', () {
      expect(rfidTagRepositoryProvider, isNotNull);
    });

    test('rfidTagsProvider is defined', () {
      expect(rfidTagsProvider, isNotNull);
    });

    test('allRfidTagsProvider is defined', () {
      expect(allRfidTagsProvider, isNotNull);
    });

    test('rfidTagByEpcProvider is defined', () {
      expect(rfidTagByEpcProvider, isNotNull);
    });

    test('rfidTagByIdProvider is defined', () {
      expect(rfidTagByIdProvider, isNotNull);
    });

    test('rfidTagCountProvider is defined', () {
      expect(rfidTagCountProvider, isNotNull);
    });

    test('totalRfidTagCountProvider is defined', () {
      expect(totalRfidTagCountProvider, isNotNull);
    });

    test('rfidTagManagementProvider is defined', () {
      expect(rfidTagManagementProvider, isNotNull);
    });

    test('tagFilterProvider is defined', () {
      expect(tagFilterProvider, isNotNull);
    });

    test('filteredRfidTagsProvider is defined', () {
      expect(filteredRfidTagsProvider, isNotNull);
    });
  });
}
