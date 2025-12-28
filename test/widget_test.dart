import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saturday_consumer_app/app.dart';

void main() {
  testWidgets('App loads with bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SaturdayApp(),
      ),
    );

    // Allow time for router to initialize
    await tester.pumpAndSettle();

    // Verify bottom navigation is present with correct tabs
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });

  testWidgets('Now Playing screen is the initial route',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SaturdayApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Now Playing screen content is visible
    expect(find.text('No record playing'), findsOneWidget);
  });
}
