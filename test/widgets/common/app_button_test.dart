import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/widgets/common/app_button.dart';
import 'package:saturday_app/config/theme.dart';

void main() {
  group('AppButton', () {
    testWidgets('renders text correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Test Button',
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('renders with icon when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Test Button',
              icon: Icons.login,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped', (WidgetTester tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Test Button',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Test Button'));
      await tester.pump();

      expect(pressed, isTrue);
    });

    testWidgets('is disabled when onPressed is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Test Button',
              onPressed: null,
            ),
          ),
        ),
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('shows loading indicator when isLoading is true', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Test Button',
              isLoading: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Test Button'), findsNothing);
    });

    testWidgets('is disabled when isLoading is true', (WidgetTester tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Test Button',
              isLoading: true,
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      // Try to tap the button (should not work)
      await tester.tap(find.byType(AppButton));
      await tester.pump();

      expect(pressed, isFalse);
    });

    group('Primary style', () {
      testWidgets('renders with correct colors', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppButton(
                text: 'Primary Button',
                style: AppButtonStyle.primary,
                onPressed: () {},
              ),
            ),
          ),
        );

        final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
        final buttonStyle = button.style!;

        expect(
          buttonStyle.backgroundColor?.resolve({}),
          equals(SaturdayColors.primaryDark),
        );
      });

      testWidgets('has correct height', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppButton(
                text: 'Primary Button',
                onPressed: () {},
              ),
            ),
          ),
        );

        final sizedBox = tester.widget<SizedBox>(
          find.ancestor(
            of: find.byType(ElevatedButton),
            matching: find.byType(SizedBox),
          ),
        );

        expect(sizedBox.height, equals(48));
      });
    });

    group('Secondary style', () {
      testWidgets('renders as OutlinedButton', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppButton(
                text: 'Secondary Button',
                style: AppButtonStyle.secondary,
                onPressed: () {},
              ),
            ),
          ),
        );

        expect(find.byType(OutlinedButton), findsOneWidget);
      });

      testWidgets('has border with correct color', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppButton(
                text: 'Secondary Button',
                style: AppButtonStyle.secondary,
                onPressed: () {},
              ),
            ),
          ),
        );

        final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
        final side = button.style!.side?.resolve({});

        expect(side?.color, equals(SaturdayColors.primaryDark));
      });
    });

    group('Text style', () {
      testWidgets('renders as TextButton', (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AppButton(
                text: 'Text Button',
                style: AppButtonStyle.text,
                onPressed: () {},
              ),
            ),
          ),
        );

        expect(find.byType(TextButton), findsOneWidget);
      });
    });

    testWidgets('respects custom width', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              text: 'Wide Button',
              width: 300,
              onPressed: () {},
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byType(ElevatedButton),
          matching: find.byType(SizedBox),
        ),
      );

      expect(sizedBox.width, equals(300));
    });
  });
}
