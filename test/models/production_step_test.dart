import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/production_step.dart';

void main() {
  group('ProductionStep', () {
    final now = DateTime.now();
    final step = ProductionStep(
      id: 'step-123',
      productId: 'prod-456',
      name: 'CNC Machining',
      description: 'Machine the wood frame',
      stepOrder: 1,
      fileUrl: 'https://storage.example.com/file.gcode',
      fileName: 'frame.gcode',
      fileType: 'gcode',
      createdAt: now,
      updatedAt: now,
    );

    test('creates step with all fields', () {
      expect(step.id, 'step-123');
      expect(step.productId, 'prod-456');
      expect(step.name, 'CNC Machining');
      expect(step.description, 'Machine the wood frame');
      expect(step.stepOrder, 1);
      expect(step.fileUrl, 'https://storage.example.com/file.gcode');
      expect(step.fileName, 'frame.gcode');
      expect(step.fileType, 'gcode');
    });

    test('creates step without optional fields', () {
      final minimalStep = ProductionStep(
        id: 'step-123',
        productId: 'prod-456',
        name: 'Assembly',
        stepOrder: 2,
        createdAt: now,
        updatedAt: now,
      );

      expect(minimalStep.description, null);
      expect(minimalStep.fileUrl, null);
      expect(minimalStep.fileName, null);
      expect(minimalStep.fileType, null);
    });

    test('isValid returns true for valid step', () {
      expect(step.isValid(), true);
    });

    test('isValid returns false for step with zero or negative stepOrder', () {
      final invalidStep = step.copyWith(stepOrder: 0);
      expect(invalidStep.isValid(), false);

      final negativeStep = step.copyWith(stepOrder: -1);
      expect(negativeStep.isValid(), false);
    });

    test('isValid returns false for step with empty name', () {
      final invalidStep = step.copyWith(name: '');
      expect(invalidStep.isValid(), false);
    });

    test('fromJson creates step correctly', () {
      final json = {
        'id': 'step-123',
        'product_id': 'prod-456',
        'name': 'CNC Machining',
        'description': 'Machine the wood frame',
        'step_order': 1,
        'file_url': 'https://storage.example.com/file.gcode',
        'file_name': 'frame.gcode',
        'file_type': 'gcode',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = ProductionStep.fromJson(json);
      expect(fromJson.id, 'step-123');
      expect(fromJson.name, 'CNC Machining');
      expect(fromJson.stepOrder, 1);
      expect(fromJson.fileUrl, 'https://storage.example.com/file.gcode');
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'id': 'step-123',
        'product_id': 'prod-456',
        'name': 'Assembly',
        'step_order': 2,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = ProductionStep.fromJson(json);
      expect(fromJson.description, null);
      expect(fromJson.fileUrl, null);
      expect(fromJson.fileName, null);
      expect(fromJson.fileType, null);
    });

    test('toJson converts step correctly', () {
      final json = step.toJson();
      expect(json['id'], 'step-123');
      expect(json['product_id'], 'prod-456');
      expect(json['name'], 'CNC Machining');
      expect(json['step_order'], 1);
      expect(json['file_url'], 'https://storage.example.com/file.gcode');
      expect(json['file_name'], 'frame.gcode');
      expect(json['file_type'], 'gcode');
    });

    test('copyWith creates new instance with updated fields', () {
      final updated = step.copyWith(
        name: 'Updated Step',
        stepOrder: 3,
      );

      expect(updated.id, 'step-123'); // unchanged
      expect(updated.name, 'Updated Step'); // changed
      expect(updated.stepOrder, 3); // changed
    });

    test('equality works correctly', () {
      final step1 = ProductionStep(
        id: 'step-123',
        productId: 'prod-456',
        name: 'CNC Machining',
        stepOrder: 1,
        createdAt: now,
        updatedAt: now,
      );

      final step2 = ProductionStep(
        id: 'step-123',
        productId: 'prod-456',
        name: 'CNC Machining',
        stepOrder: 1,
        createdAt: now,
        updatedAt: now,
      );

      expect(step1, equals(step2));
      expect(step1.hashCode, equals(step2.hashCode));
    });

    test('toString includes key information', () {
      final str = step.toString();
      expect(str, contains('step-123'));
      expect(str, contains('CNC Machining'));
      expect(str, contains('1'));
    });

    test('serialization round-trip preserves data', () {
      final json = step.toJson();
      final fromJson = ProductionStep.fromJson(json);
      expect(fromJson, equals(step));
    });

    test('validates positive step order requirement', () {
      final validStep = ProductionStep(
        id: 'step-1',
        productId: 'prod-1',
        name: 'Test',
        stepOrder: 1,
        createdAt: now,
        updatedAt: now,
      );
      expect(validStep.isValid(), true);

      final invalidStep = validStep.copyWith(stepOrder: 0);
      expect(invalidStep.isValid(), false);
    });

    test('validates name requirement', () {
      final validStep = ProductionStep(
        id: 'step-1',
        productId: 'prod-1',
        name: 'Valid Name',
        stepOrder: 1,
        createdAt: now,
        updatedAt: now,
      );
      expect(validStep.isValid(), true);

      final invalidStep = validStep.copyWith(name: '');
      expect(invalidStep.isValid(), false);
    });

    group('isFirmwareStep', () {
      test('returns true when step name contains "firmware"', () {
        final firmwareStep = step.copyWith(name: 'Flash Firmware');
        expect(firmwareStep.isFirmwareStep(), true);

        final firmwareStep2 = step.copyWith(name: 'Firmware Provisioning');
        expect(firmwareStep2.isFirmwareStep(), true);

        final firmwareStep3 = step.copyWith(name: 'Update FIRMWARE');
        expect(firmwareStep3.isFirmwareStep(), true);
      });

      test('returns true when step name contains "flash" and "device"', () {
        final flashStep = step.copyWith(name: 'Flash Device');
        expect(flashStep.isFirmwareStep(), true);

        final flashStep2 = step.copyWith(name: 'Flash all devices');
        expect(flashStep2.isFirmwareStep(), true);
      });

      test('returns true when description contains firmware keywords', () {
        final step1 = step.copyWith(
          name: 'Step 3',
          description: 'Firmware provisioning for ESP32',
        );
        expect(step1.isFirmwareStep(), true);

        final step2 = step.copyWith(
          name: 'Step 4',
          description: 'Flash firmware to all devices',
        );
        expect(step2.isFirmwareStep(), true);
      });

      test('returns false when step is not firmware-related', () {
        final regularStep = step.copyWith(
          name: 'CNC Machining',
          description: 'Machine the wood frame',
        );
        expect(regularStep.isFirmwareStep(), false);

        final assemblyStep = step.copyWith(
          name: 'Assembly',
          description: 'Assemble all components',
        );
        expect(assemblyStep.isFirmwareStep(), false);
      });

      test('returns false when name contains "flash" but not "device"', () {
        final flashStep = step.copyWith(name: 'Flash Photography');
        expect(flashStep.isFirmwareStep(), false);
      });

      test('is case-insensitive', () {
        final step1 = step.copyWith(name: 'FIRMWARE UPDATE');
        expect(step1.isFirmwareStep(), true);

        final step2 = step.copyWith(name: 'firmware update');
        expect(step2.isFirmwareStep(), true);

        final step3 = step.copyWith(
          name: 'Step 5',
          description: 'FLASH FIRMWARE',
        );
        expect(step3.isFirmwareStep(), true);
      });

      test('handles null description gracefully', () {
        final stepWithoutDesc = ProductionStep(
          id: 'step-1',
          productId: 'prod-1',
          name: 'Regular Step',
          stepOrder: 1,
          createdAt: now,
          updatedAt: now,
        );
        expect(stepWithoutDesc.isFirmwareStep(), false);
      });
    });
  });
}
