import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/user.dart';

void main() {
  group('User', () {
    final now = DateTime.now();
    final testUser = User(
      id: 'test-uuid-123',
      googleId: 'google-id-456',
      email: 'test@saturdayvinyl.com',
      fullName: 'Test User',
      isAdmin: false,
      isActive: true,
      createdAt: now,
      lastLogin: now,
    );

    group('fromJson', () {
      test('creates User from valid JSON', () {
        final json = {
          'id': 'test-uuid-123',
          'google_id': 'google-id-456',
          'email': 'test@saturdayvinyl.com',
          'full_name': 'Test User',
          'is_admin': false,
          'is_active': true,
          'created_at': now.toIso8601String(),
          'last_login': now.toIso8601String(),
        };

        final user = User.fromJson(json);

        expect(user.id, 'test-uuid-123');
        expect(user.googleId, 'google-id-456');
        expect(user.email, 'test@saturdayvinyl.com');
        expect(user.fullName, 'Test User');
        expect(user.isAdmin, false);
        expect(user.isActive, true);
        expect(user.createdAt.toIso8601String(), now.toIso8601String());
        expect(user.lastLogin?.toIso8601String(), now.toIso8601String());
      });

      test('handles null fullName', () {
        final json = {
          'id': 'test-uuid-123',
          'google_id': 'google-id-456',
          'email': 'test@saturdayvinyl.com',
          'full_name': null,
          'is_admin': false,
          'is_active': true,
          'created_at': now.toIso8601String(),
          'last_login': null,
        };

        final user = User.fromJson(json);

        expect(user.fullName, null);
        expect(user.lastLogin, null);
      });

      test('defaults isAdmin to false if not provided', () {
        final json = {
          'id': 'test-uuid-123',
          'google_id': 'google-id-456',
          'email': 'test@saturdayvinyl.com',
          'created_at': now.toIso8601String(),
        };

        final user = User.fromJson(json);

        expect(user.isAdmin, false);
        expect(user.isActive, true);
      });
    });

    group('toJson', () {
      test('converts User to JSON correctly', () {
        final json = testUser.toJson();

        expect(json['id'], 'test-uuid-123');
        expect(json['google_id'], 'google-id-456');
        expect(json['email'], 'test@saturdayvinyl.com');
        expect(json['full_name'], 'Test User');
        expect(json['is_admin'], false);
        expect(json['is_active'], true);
        expect(json['created_at'], now.toIso8601String());
        expect(json['last_login'], now.toIso8601String());
      });

      test('handles null values correctly', () {
        final user = User(
          id: 'test-uuid-123',
          googleId: 'google-id-456',
          email: 'test@saturdayvinyl.com',
          fullName: null,
          isAdmin: false,
          isActive: true,
          createdAt: now,
          lastLogin: null,
        );

        final json = user.toJson();

        expect(json['full_name'], null);
        expect(json['last_login'], null);
      });
    });

    group('copyWith', () {
      test('creates new instance with updated fields', () {
        final updated = testUser.copyWith(
          fullName: 'Updated Name',
          isAdmin: true,
        );

        expect(updated.id, testUser.id);
        expect(updated.googleId, testUser.googleId);
        expect(updated.email, testUser.email);
        expect(updated.fullName, 'Updated Name');
        expect(updated.isAdmin, true);
        expect(updated.isActive, testUser.isActive);
        expect(updated.createdAt, testUser.createdAt);
        expect(updated.lastLogin, testUser.lastLogin);
      });

      test('returns identical copy if no fields updated', () {
        final copy = testUser.copyWith();

        expect(copy.id, testUser.id);
        expect(copy.googleId, testUser.googleId);
        expect(copy.email, testUser.email);
        expect(copy.fullName, testUser.fullName);
        expect(copy.isAdmin, testUser.isAdmin);
        expect(copy.isActive, testUser.isActive);
      });
    });

    group('equality', () {
      test('two Users with same values are equal', () {
        final user1 = User(
          id: 'test-uuid-123',
          googleId: 'google-id-456',
          email: 'test@saturdayvinyl.com',
          fullName: 'Test User',
          isAdmin: false,
          isActive: true,
          createdAt: now,
          lastLogin: now,
        );

        final user2 = User(
          id: 'test-uuid-123',
          googleId: 'google-id-456',
          email: 'test@saturdayvinyl.com',
          fullName: 'Test User',
          isAdmin: false,
          isActive: true,
          createdAt: now,
          lastLogin: now,
        );

        expect(user1, equals(user2));
        expect(user1.hashCode, equals(user2.hashCode));
      });

      test('two Users with different values are not equal', () {
        final user1 = testUser;
        final user2 = testUser.copyWith(email: 'different@saturdayvinyl.com');

        expect(user1, isNot(equals(user2)));
        expect(user1.hashCode, isNot(equals(user2.hashCode)));
      });
    });

    group('toString', () {
      test('returns formatted string representation', () {
        final str = testUser.toString();

        expect(str, contains('User'));
        expect(str, contains('test-uuid-123'));
        expect(str, contains('test@saturdayvinyl.com'));
        expect(str, contains('false')); // isAdmin
        expect(str, contains('true')); // isActive
      });
    });
  });
}
