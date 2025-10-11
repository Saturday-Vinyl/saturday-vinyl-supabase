import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/widgets/common/error_state.dart';

void main() {
  group('ErrorState', () {
    testWidgets('displays error icon and message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: 'Something went wrong',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('displays details when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: 'Something went wrong',
              details: 'Error details here',
            ),
          ),
        ),
      );

      expect(find.text('Error details here'), findsOneWidget);
    });

    testWidgets('displays retry button when provided', (tester) async {
      bool retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: 'Something went wrong',
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      expect(retryCalled, true);
    });

    testWidgets('does not display retry button when not provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: 'Something went wrong',
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('centers content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: 'Something went wrong',
            ),
          ),
        ),
      );

      final center = find.byType(Center);
      expect(center, findsOneWidget);
    });
  });
}
