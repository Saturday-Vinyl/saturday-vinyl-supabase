import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/widgets/common/user_avatar.dart';
import 'package:saturday_app/config/theme.dart';

void main() {
  group('UserAvatar', () {
    testWidgets('renders with initials from full name', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              displayName: 'John Doe',
            ),
          ),
        ),
      );

      expect(find.text('JD'), findsOneWidget);
    });

    testWidgets('renders with initial from single name', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              displayName: 'John',
            ),
          ),
        ),
      );

      expect(find.text('J'), findsOneWidget);
    });

    testWidgets('renders with initial from email when no display name', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              email: 'john@example.com',
            ),
          ),
        ),
      );

      expect(find.text('J'), findsOneWidget);
    });

    testWidgets('renders question mark when no display name or email', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('has correct size for small avatar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              displayName: 'Test User',
              size: AvatarSize.small,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byType(ClipOval),
          matching: find.byType(Container),
        ).first,
      );

      expect(container.constraints?.minWidth, equals(32));
      expect(container.constraints?.minHeight, equals(32));
    });

    testWidgets('has correct size for medium avatar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              displayName: 'Test User',
              size: AvatarSize.medium,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byType(ClipOval),
          matching: find.byType(Container),
        ).first,
      );

      expect(container.constraints?.minWidth, equals(40));
      expect(container.constraints?.minHeight, equals(40));
    });

    testWidgets('has correct size for large avatar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              displayName: 'Test User',
              size: AvatarSize.large,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byType(ClipOval),
          matching: find.byType(Container),
        ).first,
      );

      expect(container.constraints?.minWidth, equals(80));
      expect(container.constraints?.minHeight, equals(80));
    });

    testWidgets('has correct background color', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              displayName: 'Test User',
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byType(ClipOval),
          matching: find.byType(Container),
        ).first,
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(SaturdayColors.primaryDark));
    });

    testWidgets('is circular', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserAvatar(
              displayName: 'Test User',
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.byType(ClipOval),
          matching: find.byType(Container),
        ).first,
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, equals(BoxShape.circle));
    });
  });
}
