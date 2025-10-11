import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/permission.dart';
import 'package:saturday_app/models/user.dart';
import 'package:saturday_app/providers/users_provider.dart';
import 'package:saturday_app/screens/users/user_detail_screen.dart';

void main() {
  group('UserDetailScreen', () {
    late User testUser;
    late List<Permission> testPermissions;
    late Map<String, bool> permissionMap;

    setUp(() {
      testUser = User(
        id: '1',
        googleId: 'google-1',
        email: 'user@saturdayvinyl.com',
        fullName: 'Test User',
        isAdmin: false,
        isActive: true,
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );

      testPermissions = [
        Permission(
          id: 'perm1',
          name: 'manage_products',
          description: 'Manage products',
          createdAt: DateTime.now(),
        ),
        Permission(
          id: 'perm2',
          name: 'manage_firmware',
          description: 'Manage firmware',
          createdAt: DateTime.now(),
        ),
      ];

      // Map of permission ID -> has permission
      permissionMap = {
        'perm1': true,  // User has manage_products
        'perm2': false, // User doesn't have manage_firmware
      };
    });

    testWidgets('displays user details', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPermissionsProvider.overrideWith((ref) => Future.value(testPermissions)),
            userPermissionDetailsProvider(testUser.id).overrideWith((ref) => Future.value(permissionMap)),
          ],
          child: MaterialApp(
            home: UserDetailScreen(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Test User'), findsOneWidget);
      expect(find.text('user@saturdayvinyl.com'), findsOneWidget);
    });

    testWidgets('displays permission checklist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPermissionsProvider.overrideWith((ref) => Future.value(testPermissions)),
            userPermissionDetailsProvider(testUser.id).overrideWith((ref) => Future.value(permissionMap)),
          ],
          child: MaterialApp(
            home: UserDetailScreen(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show both permissions
      expect(find.text('Manage products'), findsOneWidget);
      expect(find.text('Manage firmware'), findsOneWidget);

      // Should have checkboxes
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
    });

    testWidgets('shows granted permission as checked', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPermissionsProvider.overrideWith((ref) => Future.value(testPermissions)),
            userPermissionDetailsProvider(testUser.id).overrideWith((ref) => Future.value(permissionMap)),
          ],
          child: MaterialApp(
            home: UserDetailScreen(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the checkbox for manage_products (which is granted)
      final checkboxes = find.byType(CheckboxListTile);
      final firstCheckbox = tester.widget<CheckboxListTile>(checkboxes.first);

      // The first permission (manage_products) should be checked
      expect(firstCheckbox.value, true);
    });

    testWidgets('displays admin notice for admin users', (tester) async {
      final adminUser = testUser.copyWith(isAdmin: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPermissionsProvider.overrideWith((ref) => Future.value(testPermissions)),
            userPermissionDetailsProvider(adminUser.id).overrideWith((ref) => Future.value(permissionMap)),
          ],
          child: MaterialApp(
            home: UserDetailScreen(user: adminUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Admin users have all permissions by default.'), findsOneWidget);
    });

    testWidgets('shows inactive badge for inactive users', (tester) async {
      final inactiveUser = testUser.copyWith(isActive: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPermissionsProvider.overrideWith((ref) => Future.value(testPermissions)),
            userPermissionDetailsProvider(inactiveUser.id).overrideWith((ref) => Future.value(permissionMap)),
          ],
          child: MaterialApp(
            home: UserDetailScreen(user: inactiveUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('INACTIVE'), findsOneWidget);
    });

    testWidgets('shows loading state while fetching permissions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPermissionsProvider.overrideWith(
              (ref) => Future.delayed(const Duration(seconds: 10), () => testPermissions),
            ),
            userPermissionDetailsProvider(testUser.id).overrideWith(
              (ref) => Future.delayed(const Duration(seconds: 10), () => permissionMap),
            ),
          ],
          child: MaterialApp(
            home: UserDetailScreen(user: testUser),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state on permission load failure', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPermissionsProvider.overrideWith(
              (ref) => Future.error(Exception('Failed to load')),
            ),
            userPermissionDetailsProvider(testUser.id).overrideWith(
              (ref) => Future.value(permissionMap),
            ),
          ],
          child: MaterialApp(
            home: UserDetailScreen(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Error loading permissions'), findsOneWidget);
    });
  });
}
