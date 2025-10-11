import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/widgets/products/production_step_item.dart';

void main() {
  group('ProductionStepItem', () {
    late ProductionStep testStep;

    setUp(() {
      testStep = ProductionStep(
        id: 'step-1',
        productId: 'prod-1',
        name: 'CNC Machining',
        description: 'Machine the wood frame',
        stepOrder: 1,
        fileName: 'frame.gcode',
        fileType: 'gcode',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    testWidgets('displays step number and name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(step: testStep),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('CNC Machining'), findsOneWidget);
    });

    testWidgets('displays description when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(step: testStep),
          ),
        ),
      );

      expect(find.text('Machine the wood frame'), findsOneWidget);
    });

    testWidgets('displays file icon when file attached', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(step: testStep),
          ),
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.text('frame.gcode'), findsOneWidget);
    });

    testWidgets('shows edit and delete buttons when editable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(
              step: testStep,
              isEditable: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('hides edit and delete buttons when not editable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(
              step: testStep,
              isEditable: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
    });

    testWidgets('shows drag handle when enabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(
              step: testStep,
              showDragHandle: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    });

    testWidgets('calls onEdit when edit button tapped', (tester) async {
      bool editCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(
              step: testStep,
              isEditable: true,
              onEdit: () => editCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.edit));
      expect(editCalled, true);
    });

    testWidgets('calls onDelete when delete button tapped', (tester) async {
      bool deleteCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductionStepItem(
              step: testStep,
              isEditable: true,
              onDelete: () => deleteCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.delete));
      expect(deleteCalled, true);
    });
  });
}
