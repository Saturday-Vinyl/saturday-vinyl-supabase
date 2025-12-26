import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/rfid_tag.dart';

void main() {
  group('RfidTagStatus', () {
    test('value returns correct string for each status', () {
      expect(RfidTagStatus.generated.value, 'generated');
      expect(RfidTagStatus.written.value, 'written');
      expect(RfidTagStatus.locked.value, 'locked');
      expect(RfidTagStatus.failed.value, 'failed');
      expect(RfidTagStatus.retired.value, 'retired');
    });

    test('fromString returns correct status for each value', () {
      expect(
          RfidTagStatusExtension.fromString('generated'), RfidTagStatus.generated);
      expect(RfidTagStatusExtension.fromString('written'), RfidTagStatus.written);
      expect(RfidTagStatusExtension.fromString('locked'), RfidTagStatus.locked);
      expect(RfidTagStatusExtension.fromString('failed'), RfidTagStatus.failed);
      expect(RfidTagStatusExtension.fromString('retired'), RfidTagStatus.retired);
    });

    test('fromString throws for invalid value', () {
      expect(
        () => RfidTagStatusExtension.fromString('invalid'),
        throwsArgumentError,
      );
    });
  });

  group('RfidTag', () {
    final now = DateTime.now();
    final tag = RfidTag(
      id: 'tag-123',
      epcIdentifier: '5356A1B2C3D4E5F67890ABCD',
      tid: 'E2003412B802011234567890',
      status: RfidTagStatus.locked,
      createdAt: now,
      updatedAt: now,
      writtenAt: now.subtract(const Duration(minutes: 2)),
      lockedAt: now.subtract(const Duration(minutes: 1)),
      createdBy: 'user-456',
    );

    test('creates tag with all fields', () {
      expect(tag.id, 'tag-123');
      expect(tag.epcIdentifier, '5356A1B2C3D4E5F67890ABCD');
      expect(tag.tid, 'E2003412B802011234567890');
      expect(tag.status, RfidTagStatus.locked);
      expect(tag.createdBy, 'user-456');
    });

    test('creates tag without optional fields', () {
      final minimalTag = RfidTag(
        id: 'tag-789',
        epcIdentifier: '5356000000000000000000FF',
        status: RfidTagStatus.generated,
        createdAt: now,
        updatedAt: now,
      );

      expect(minimalTag.tid, null);
      expect(minimalTag.writtenAt, null);
      expect(minimalTag.lockedAt, null);
      expect(minimalTag.createdBy, null);
    });

    group('isSaturdayTag', () {
      test('returns true for tags with 5356 prefix', () {
        expect(tag.isSaturdayTag, true);
      });

      test('returns true for lowercase prefix', () {
        final lowercaseTag = RfidTag(
          id: 'tag-1',
          epcIdentifier: '5356abcdef123456789012ab',
          status: RfidTagStatus.generated,
          createdAt: now,
          updatedAt: now,
        );
        expect(lowercaseTag.isSaturdayTag, true);
      });

      test('returns false for tags without 5356 prefix', () {
        final nonSaturdayTag = RfidTag(
          id: 'tag-2',
          epcIdentifier: '000000000000000000000000',
          status: RfidTagStatus.generated,
          createdAt: now,
          updatedAt: now,
        );
        expect(nonSaturdayTag.isSaturdayTag, false);
      });

      test('returns false for different prefix', () {
        final otherTag = RfidTag(
          id: 'tag-3',
          epcIdentifier: 'ABCD1234567890ABCDEF1234',
          status: RfidTagStatus.generated,
          createdAt: now,
          updatedAt: now,
        );
        expect(otherTag.isSaturdayTag, false);
      });
    });

    group('formattedEpc', () {
      test('formats EPC with dashes correctly', () {
        expect(tag.formattedEpc, '5356-A1B2-C3D4-E5F6-7890-ABCD');
      });

      test('converts to uppercase', () {
        final lowercaseTag = RfidTag(
          id: 'tag-1',
          epcIdentifier: '5356abcdef1234567890abcd',
          status: RfidTagStatus.generated,
          createdAt: now,
          updatedAt: now,
        );
        expect(lowercaseTag.formattedEpc, '5356-ABCD-EF12-3456-7890-ABCD');
      });

      test('returns raw EPC if wrong length', () {
        final shortTag = RfidTag(
          id: 'tag-1',
          epcIdentifier: '5356ABC',
          status: RfidTagStatus.generated,
          createdAt: now,
          updatedAt: now,
        );
        expect(shortTag.formattedEpc, '5356ABC');
      });
    });

    group('generateEpc', () {
      test('generates EPC with correct length', () {
        final epc = RfidTag.generateEpc();
        expect(epc.length, 24);
      });

      test('generates EPC starting with 5356 prefix', () {
        final epc = RfidTag.generateEpc();
        expect(epc.startsWith('5356'), true);
      });

      test('generates valid hex characters only', () {
        final epc = RfidTag.generateEpc();
        expect(RegExp(r'^[0-9A-F]{24}$').hasMatch(epc), true);
      });

      test('generates unique values', () {
        final epcs = <String>{};
        for (var i = 0; i < 100; i++) {
          epcs.add(RfidTag.generateEpc());
        }
        // All 100 should be unique
        expect(epcs.length, 100);
      });

      test('generates uppercase hex', () {
        final epc = RfidTag.generateEpc();
        expect(epc, epc.toUpperCase());
      });

      test('accepts custom random for deterministic testing', () {
        final random1 = Random(42);
        final random2 = Random(42);
        final epc1 = RfidTag.generateEpc(random: random1);
        final epc2 = RfidTag.generateEpc(random: random2);
        expect(epc1, epc2);
      });
    });

    group('isValidEpc', () {
      test('returns true for valid 24-char hex', () {
        expect(RfidTag.isValidEpc('5356A1B2C3D4E5F67890ABCD'), true);
        expect(RfidTag.isValidEpc('000000000000000000000000'), true);
        expect(RfidTag.isValidEpc('FFFFFFFFFFFFFFFFFFFFFFFF'), true);
      });

      test('returns true for lowercase hex', () {
        expect(RfidTag.isValidEpc('5356a1b2c3d4e5f67890abcd'), true);
      });

      test('returns true for mixed case hex', () {
        expect(RfidTag.isValidEpc('5356A1b2C3d4E5f67890AbCd'), true);
      });

      test('returns false for wrong length', () {
        expect(RfidTag.isValidEpc('5356'), false);
        expect(RfidTag.isValidEpc('5356A1B2C3D4E5F67890ABCDEF'), false);
        expect(RfidTag.isValidEpc(''), false);
      });

      test('returns false for non-hex characters', () {
        expect(RfidTag.isValidEpc('5356A1B2C3D4E5F67890ABCG'), false);
        expect(RfidTag.isValidEpc('5356A1B2C3D4E5F67890ABC!'), false);
        expect(RfidTag.isValidEpc('5356A1B2C3D4E5F6 890ABCD'), false);
      });
    });

    group('fromJson', () {
      test('creates tag from JSON correctly', () {
        final json = {
          'id': 'tag-123',
          'epc_identifier': '5356A1B2C3D4E5F67890ABCD',
          'tid': 'E2003412B802011234567890',
          'status': 'locked',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'written_at': now.toIso8601String(),
          'locked_at': now.toIso8601String(),
          'created_by': 'user-456',
        };

        final fromJson = RfidTag.fromJson(json);
        expect(fromJson.id, 'tag-123');
        expect(fromJson.epcIdentifier, '5356A1B2C3D4E5F67890ABCD');
        expect(fromJson.tid, 'E2003412B802011234567890');
        expect(fromJson.status, RfidTagStatus.locked);
        expect(fromJson.createdBy, 'user-456');
      });

      test('handles null optional fields', () {
        final json = {
          'id': 'tag-123',
          'epc_identifier': '5356A1B2C3D4E5F67890ABCD',
          'tid': null,
          'status': 'generated',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
          'written_at': null,
          'locked_at': null,
          'created_by': null,
        };

        final fromJson = RfidTag.fromJson(json);
        expect(fromJson.tid, null);
        expect(fromJson.writtenAt, null);
        expect(fromJson.lockedAt, null);
        expect(fromJson.createdBy, null);
      });

      test('parses all status values', () {
        for (final status in RfidTagStatus.values) {
          final json = {
            'id': 'tag-1',
            'epc_identifier': '5356A1B2C3D4E5F67890ABCD',
            'status': status.value,
            'created_at': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          };
          final fromJson = RfidTag.fromJson(json);
          expect(fromJson.status, status);
        }
      });
    });

    group('toJson', () {
      test('converts tag to JSON correctly', () {
        final json = tag.toJson();
        expect(json['id'], 'tag-123');
        expect(json['epc_identifier'], '5356A1B2C3D4E5F67890ABCD');
        expect(json['tid'], 'E2003412B802011234567890');
        expect(json['status'], 'locked');
        expect(json['created_by'], 'user-456');
      });

      test('includes null fields', () {
        final minimalTag = RfidTag(
          id: 'tag-789',
          epcIdentifier: '5356000000000000000000FF',
          status: RfidTagStatus.generated,
          createdAt: now,
          updatedAt: now,
        );

        final json = minimalTag.toJson();
        expect(json['tid'], null);
        expect(json['written_at'], null);
        expect(json['locked_at'], null);
        expect(json['created_by'], null);
      });
    });

    group('toInsertJson', () {
      test('excludes id and auto-generated timestamps', () {
        final insertJson = tag.toInsertJson();
        expect(insertJson.containsKey('id'), false);
        expect(insertJson.containsKey('created_at'), false);
        expect(insertJson.containsKey('updated_at'), false);
      });

      test('includes required insert fields', () {
        final insertJson = tag.toInsertJson();
        expect(insertJson['epc_identifier'], '5356A1B2C3D4E5F67890ABCD');
        expect(insertJson['status'], 'locked');
      });
    });

    group('copyWith', () {
      test('creates new instance with updated fields', () {
        final updated = tag.copyWith(
          status: RfidTagStatus.retired,
          tid: 'NEW_TID_12345',
        );

        expect(updated.id, 'tag-123'); // unchanged
        expect(updated.epcIdentifier, '5356A1B2C3D4E5F67890ABCD'); // unchanged
        expect(updated.status, RfidTagStatus.retired); // changed
        expect(updated.tid, 'NEW_TID_12345'); // changed
      });

      test('creates new instance with all original values when no args', () {
        final copied = tag.copyWith();
        expect(copied, equals(tag));
        expect(identical(copied, tag), false);
      });
    });

    group('equality', () {
      test('equal tags have same hashCode', () {
        final tag1 = RfidTag(
          id: 'tag-123',
          epcIdentifier: '5356A1B2C3D4E5F67890ABCD',
          status: RfidTagStatus.locked,
          createdAt: now,
          updatedAt: now,
        );

        final tag2 = RfidTag(
          id: 'tag-123',
          epcIdentifier: '5356A1B2C3D4E5F67890ABCD',
          status: RfidTagStatus.locked,
          createdAt: now,
          updatedAt: now,
        );

        expect(tag1, equals(tag2));
        expect(tag1.hashCode, equals(tag2.hashCode));
      });

      test('different status makes tags unequal', () {
        final tag1 = tag;
        final tag2 = tag.copyWith(status: RfidTagStatus.retired);
        expect(tag1, isNot(equals(tag2)));
      });

      test('different EPC makes tags unequal', () {
        final tag1 = tag;
        final tag2 = tag.copyWith(epcIdentifier: '5356FFFFFFFFFFFFFFFFFFFF');
        expect(tag1, isNot(equals(tag2)));
      });
    });

    group('serialization round-trip', () {
      test('preserves all data through JSON serialization', () {
        final json = tag.toJson();
        final fromJson = RfidTag.fromJson(json);
        expect(fromJson, equals(tag));
      });

      test('preserves minimal tag through serialization', () {
        final minimalTag = RfidTag(
          id: 'tag-minimal',
          epcIdentifier: '5356000000000000000000FF',
          status: RfidTagStatus.generated,
          createdAt: now,
          updatedAt: now,
        );

        final json = minimalTag.toJson();
        final fromJson = RfidTag.fromJson(json);
        expect(fromJson, equals(minimalTag));
      });
    });

    group('toString', () {
      test('includes key information', () {
        final str = tag.toString();
        expect(str, contains('tag-123'));
        expect(str, contains('5356-A1B2-C3D4-E5F6-7890-ABCD'));
        expect(str, contains('locked'));
      });
    });

    group('constants', () {
      test('epcPrefix is 5356', () {
        expect(RfidTag.epcPrefix, '5356');
      });

      test('epcHexLength is 24', () {
        expect(RfidTag.epcHexLength, 24);
      });

      test('randomHexLength is 20', () {
        expect(RfidTag.randomHexLength, 20);
      });
    });
  });
}
