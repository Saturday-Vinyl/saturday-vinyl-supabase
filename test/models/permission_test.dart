import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/permission.dart';

void main() {
  group('Permission', () {
    final now = DateTime.now();
    final testPermission = Permission(
      id: 'perm-uuid-123',
      name: Permission.manageProducts,
      description: 'Allows managing product catalog',
      createdAt: now,
    );

    group('constants', () {
      test('predefined permission names are correct', () {
        expect(Permission.manageProducts, 'manage_products');
        expect(Permission.manageFirmware, 'manage_firmware');
        expect(Permission.manageProduction, 'manage_production');
      });
    });

    group('fromJson', () {
      test('creates Permission from valid JSON', () {
        final json = {
          'id': 'perm-uuid-123',
          'name': 'manage_products',
          'description': 'Allows managing product catalog',
          'created_at': now.toIso8601String(),
        };

        final permission = Permission.fromJson(json);

        expect(permission.id, 'perm-uuid-123');
        expect(permission.name, 'manage_products');
        expect(permission.description, 'Allows managing product catalog');
        expect(
          permission.createdAt.toIso8601String(),
          now.toIso8601String(),
        );
      });

      test('handles null description', () {
        final json = {
          'id': 'perm-uuid-123',
          'name': 'manage_firmware',
          'description': null,
          'created_at': now.toIso8601String(),
        };

        final permission = Permission.fromJson(json);

        expect(permission.description, null);
      });
    });

    group('toJson', () {
      test('converts Permission to JSON correctly', () {
        final json = testPermission.toJson();

        expect(json['id'], 'perm-uuid-123');
        expect(json['name'], 'manage_products');
        expect(json['description'], 'Allows managing product catalog');
        expect(json['created_at'], now.toIso8601String());
      });

      test('handles null description correctly', () {
        final permission = Permission(
          id: 'perm-uuid-123',
          name: 'manage_firmware',
          description: null,
          createdAt: now,
        );

        final json = permission.toJson();

        expect(json['description'], null);
      });
    });

    group('copyWith', () {
      test('creates new instance with updated fields', () {
        final updated = testPermission.copyWith(
          name: Permission.manageFirmware,
          description: 'Updated description',
        );

        expect(updated.id, testPermission.id);
        expect(updated.name, Permission.manageFirmware);
        expect(updated.description, 'Updated description');
        expect(updated.createdAt, testPermission.createdAt);
      });

      test('returns identical copy if no fields updated', () {
        final copy = testPermission.copyWith();

        expect(copy.id, testPermission.id);
        expect(copy.name, testPermission.name);
        expect(copy.description, testPermission.description);
        expect(copy.createdAt, testPermission.createdAt);
      });
    });

    group('equality', () {
      test('two Permissions with same values are equal', () {
        final permission1 = Permission(
          id: 'perm-uuid-123',
          name: Permission.manageProducts,
          description: 'Test description',
          createdAt: now,
        );

        final permission2 = Permission(
          id: 'perm-uuid-123',
          name: Permission.manageProducts,
          description: 'Test description',
          createdAt: now,
        );

        expect(permission1, equals(permission2));
        expect(permission1.hashCode, equals(permission2.hashCode));
      });

      test('two Permissions with different values are not equal', () {
        final permission1 = testPermission;
        final permission2 = testPermission.copyWith(
          name: Permission.manageFirmware,
        );

        expect(permission1, isNot(equals(permission2)));
        expect(permission1.hashCode, isNot(equals(permission2.hashCode)));
      });
    });

    group('toString', () {
      test('returns formatted string representation', () {
        final str = testPermission.toString();

        expect(str, contains('Permission'));
        expect(str, contains('perm-uuid-123'));
        expect(str, contains('manage_products'));
      });
    });
  });
}
