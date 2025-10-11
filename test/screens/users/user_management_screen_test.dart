import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/user.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/users_provider.dart';
import 'package:saturday_app/screens/users/user_management_screen.dart';

void main() {
  group('UserManagementScreen', () {
    late User adminUser;
    late User regularUser;
    late List<User> testUsers;

    setUp(() {
      adminUser = User(
        id: '1',
        googleId: 'google-admin',
        email: 'admin@saturdayvinyl.com',
        fullName: 'Admin User',
        isAdmin: true,
        isActive: true,
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );

      regularUser = User(
        id: '2',
        googleId: 'google-regular',
        email: 'user@saturdayvinyl.com',
        fullName: 'Regular User',
        isAdmin: false,
        isActive: true,
        createdAt: DateTime.now(),
        lastLogin: DateTime.now(),
      );

      testUsers = [adminUser, regularUser];
    });

    testWidgets('shows access denied for non-admin users', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => Future.value(false)),
          ],
          child: const MaterialApp(
            home: UserManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Access Denied'), findsOneWidget);
      expect(find.text('You do not have permission to access this page.'), findsOneWidget);
    });

    testWidgets('shows loading state while checking admin status', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => Future.delayed(const Duration(seconds: 10), () => true)),
          ],
          child: const MaterialApp(
            home: UserManagementScreen(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows user list for admin users', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => Future.value(true)),
            allUsersProvider.overrideWith((ref) => Future.value(testUsers)),
          ],
          child: const MaterialApp(
            home: UserManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('User Management'), findsOneWidget);
      expect(find.text('Admin User'), findsOneWidget);
      expect(find.text('Regular User'), findsOneWidget);
    });

    testWidgets('search functionality filters users', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => Future.value(true)),
            allUsersProvider.overrideWith((ref) => Future.value(testUsers)),
          ],
          child: const MaterialApp(
            home: UserManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the search field and enter text
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'admin');
      await tester.pumpAndSettle();

      // Should show admin user but not regular user
      expect(find.text('Admin User'), findsOneWidget);
      expect(find.text('Regular User'), findsNothing);
    });

    testWidgets('shows admin badge for admin users', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => Future.value(true)),
            allUsersProvider.overrideWith((ref) => Future.value(testUsers)),
          ],
          child: const MaterialApp(
            home: UserManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Admin badge should appear for admin user
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('shows empty state when no users', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => Future.value(true)),
            allUsersProvider.overrideWith((ref) => Future.value(<User>[])),
          ],
          child: const MaterialApp(
            home: UserManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No users found'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isAdminProvider.overrideWith((ref) => Future.value(true)),
            allUsersProvider.overrideWith((ref) => Future.error(Exception('Failed to load users'))),
          ],
          child: const MaterialApp(
            home: UserManagementScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Error loading users'), findsOneWidget);
    });
  });
}
