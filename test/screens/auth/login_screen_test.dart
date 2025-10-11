import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/config/constants.dart';
import 'package:saturday_app/screens/auth/login_screen.dart';
import 'package:saturday_app/widgets/common/app_button.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('renders app name and subtitle', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text('Production Management'), findsOneWidget);
    });

    testWidgets('renders logo', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      // Logo container should exist
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(20),
        ),
        findsOneWidget,
      );

      // S! text should exist in logo
      expect(find.text('S!'), findsOneWidget);
    });

    testWidgets('renders sign in button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.byType(AppButton), findsOneWidget);
    });

    testWidgets('renders help text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      expect(
        find.text('Sign in with your @saturdayvinyl.com account'),
        findsOneWidget,
      );
    });

    testWidgets('does not render error message initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

  });
}
