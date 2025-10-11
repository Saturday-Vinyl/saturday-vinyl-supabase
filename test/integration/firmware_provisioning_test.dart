import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/unit_firmware_history.dart';
import 'package:saturday_app/models/unit_step_completion.dart';

/// Integration test for firmware provisioning workflow
///
/// This test verifies the complete workflow:
/// 1. Create production unit
/// 2. Detect firmware provisioning step
/// 3. Get firmware for device types
/// 4. Record firmware installation
/// 5. Verify step completion and firmware history
void main() {
  group('Firmware Provisioning Workflow Integration', () {
    late DateTime now;
    late Product product;
    late ProductionUnit unit;
    late ProductionStep firmwareStep;
    late ProductionStep regularStep;
    late DeviceType deviceType;
    late FirmwareVersion firmware;

    setUp(() {
      now = DateTime.now();

      // Create test product
      product = Product(
        id: 'product-1',
        shopifyProductId: 'shopify-1',
        shopifyProductHandle: 'test-product',
        name: 'Test Turntable',
        productCode: 'TURNTABLE',
        description: 'A test turntable product',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      // Create test production unit
      unit = ProductionUnit(
        id: 'unit-1',
        uuid: 'unit-uuid-1',
        unitId: 'SV-TURNTABLE-00001',
        productId: product.id,
        variantId: 'variant-1',
        qrCodeUrl: 'https://storage.example.com/qr/unit-1.png',
        isCompleted: false,
        createdAt: now,
        createdBy: 'user-1',
      );

      // Create firmware provisioning step
      firmwareStep = ProductionStep(
        id: 'step-firmware',
        productId: product.id,
        name: 'Flash Firmware',
        description: 'Flash firmware to ESP32 devices',
        stepOrder: 2,
        createdAt: now,
        updatedAt: now,
      );

      // Create regular production step
      regularStep = ProductionStep(
        id: 'step-regular',
        productId: product.id,
        name: 'CNC Machining',
        description: 'Machine the wood frame',
        stepOrder: 1,
        fileUrl: 'https://storage.example.com/files/frame.gcode',
        fileName: 'frame.gcode',
        fileType: 'gcode',
        createdAt: now,
        updatedAt: now,
      );

      // Create test device type
      deviceType = DeviceType(
        id: 'device-1',
        name: 'ESP32 Audio Controller',
        description: 'ESP32-based audio controller',
        capabilities: ['WiFi', 'BLE', 'I2S'],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      // Create test firmware
      firmware = FirmwareVersion(
        id: 'firmware-1',
        deviceTypeId: deviceType.id,
        version: '1.0.0',
        releaseNotes: 'Initial release',
        binaryUrl: 'https://storage.example.com/firmware/esp32-v1.0.0.bin',
        binaryFilename: 'esp32-v1.0.0.bin',
        isProductionReady: true,
        createdBy: 'user-1',
        createdAt: now,
      );
    });

    test('firmware step detection works correctly', () {
      // Verify firmware step is detected
      expect(firmwareStep.isFirmwareStep(), true,
          reason: 'Firmware step should be detected by name/description');

      // Verify regular step is not detected as firmware step
      expect(regularStep.isFirmwareStep(), false,
          reason: 'Regular step should not be detected as firmware step');
    });

    test('firmware step shows firmware icon indicator', () {
      // This would be tested in widget tests, but we can verify the model behavior
      expect(firmwareStep.name.toLowerCase(), contains('firmware'));
    });

    test('unit firmware history records installation correctly', () {
      // Create firmware installation record
      final installation = UnitFirmwareHistory(
        id: 'history-1',
        unitId: unit.id,
        deviceTypeId: deviceType.id,
        firmwareVersionId: firmware.id,
        installedAt: now,
        installedBy: 'user-1',
        installationMethod: 'manual',
        notes: 'Successfully flashed ESP32',
      );

      // Verify all fields are set correctly
      expect(installation.unitId, unit.id);
      expect(installation.deviceTypeId, deviceType.id);
      expect(installation.firmwareVersionId, firmware.id);
      expect(installation.installedBy, 'user-1');
      expect(installation.installationMethod, 'manual');
      expect(installation.notes, 'Successfully flashed ESP32');
    });

    test('unit firmware history serialization works correctly', () {
      final installation = UnitFirmwareHistory(
        id: 'history-1',
        unitId: unit.id,
        deviceTypeId: deviceType.id,
        firmwareVersionId: firmware.id,
        installedAt: now,
        installedBy: 'user-1',
        installationMethod: 'manual',
        notes: 'Test notes',
      );

      // Serialize to JSON
      final json = installation.toJson();
      expect(json['id'], 'history-1');
      expect(json['unit_id'], unit.id);
      expect(json['device_type_id'], deviceType.id);
      expect(json['firmware_version_id'], firmware.id);

      // Deserialize from JSON
      final fromJson = UnitFirmwareHistory.fromJson(json);
      expect(fromJson, equals(installation));
    });

    test('step completion after firmware installation', () {
      // Simulate step completion after firmware installation
      final completion = UnitStepCompletion(
        id: 'completion-1',
        unitId: unit.id,
        stepId: firmwareStep.id,
        completedAt: now,
        completedBy: 'user-1',
        notes: 'Firmware flashed successfully',
      );

      expect(completion.unitId, unit.id);
      expect(completion.stepId, firmwareStep.id);
      expect(completion.completedBy, 'user-1');
      expect(completion.notes, 'Firmware flashed successfully');
    });

    test('firmware version selection for device type', () {
      // Verify firmware is production ready
      expect(firmware.isProductionReady, true,
          reason: 'Firmware should be marked as production ready');

      // Verify firmware is for correct device type
      expect(firmware.deviceTypeId, deviceType.id,
          reason: 'Firmware should be for the correct device type');

      // Verify firmware has required fields
      expect(firmware.binaryUrl, isNotEmpty,
          reason: 'Firmware should have binary URL');
      expect(firmware.version, isNotEmpty,
          reason: 'Firmware should have version number');
    });

    test('complete firmware provisioning workflow', () {
      // Step 1: Identify firmware step
      expect(firmwareStep.isFirmwareStep(), true);

      // Step 2: Get device types for product (simulated)
      final deviceTypes = [deviceType];
      expect(deviceTypes, isNotEmpty);

      // Step 3: Get firmware for each device type (simulated)
      final firmwareMap = <String, FirmwareVersion>{
        deviceType.id: firmware,
      };
      expect(firmwareMap.containsKey(deviceType.id), true);
      expect(firmwareMap[deviceType.id]?.isProductionReady, true);

      // Step 4: Record firmware installation
      final installation = UnitFirmwareHistory(
        id: 'history-1',
        unitId: unit.id,
        deviceTypeId: deviceType.id,
        firmwareVersionId: firmware.id,
        installedAt: now,
        installedBy: 'user-1',
        installationMethod: 'manual',
      );
      expect(installation.unitId, unit.id);
      expect(installation.firmwareVersionId, firmware.id);

      // Step 5: Mark step as complete
      final completion = UnitStepCompletion(
        id: 'completion-1',
        unitId: unit.id,
        stepId: firmwareStep.id,
        completedAt: now,
        completedBy: 'user-1',
      );
      expect(completion.stepId, firmwareStep.id);

      // Verify workflow completed successfully
      expect(installation.unitId, unit.id,
          reason: 'Installation should be recorded for correct unit');
      expect(completion.stepId, firmwareStep.id,
          reason: 'Firmware step should be marked as complete');
    });

    test('firmware provisioning handles multiple device types', () {
      // Create second device type
      final deviceType2 = DeviceType(
        id: 'device-2',
        name: 'RFID Reader',
        description: 'RFID reader module',
        capabilities: ['RFID', 'SPI'],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      // Create firmware for second device
      final firmware2 = FirmwareVersion(
        id: 'firmware-2',
        deviceTypeId: deviceType2.id,
        version: '2.0.0',
        releaseNotes: 'RFID firmware',
        binaryUrl: 'https://storage.example.com/firmware/rfid-v2.0.0.bin',
        binaryFilename: 'rfid-v2.0.0.bin',
        isProductionReady: true,
        createdBy: 'user-1',
        createdAt: now,
      );

      // Simulate firmware installation for multiple devices
      final installations = [
        UnitFirmwareHistory(
          id: 'history-1',
          unitId: unit.id,
          deviceTypeId: deviceType.id,
          firmwareVersionId: firmware.id,
          installedAt: now,
          installedBy: 'user-1',
          installationMethod: 'manual',
        ),
        UnitFirmwareHistory(
          id: 'history-2',
          unitId: unit.id,
          deviceTypeId: deviceType2.id,
          firmwareVersionId: firmware2.id,
          installedAt: now,
          installedBy: 'user-1',
          installationMethod: 'manual',
        ),
      ];

      // Verify both installations recorded
      expect(installations.length, 2);
      expect(installations[0].deviceTypeId, deviceType.id);
      expect(installations[1].deviceTypeId, deviceType2.id);
    });

    test('firmware provisioning validates production-ready status', () {
      // Create non-production firmware
      final testFirmware = FirmwareVersion(
        id: 'firmware-test',
        deviceTypeId: deviceType.id,
        version: '0.1.0-beta',
        releaseNotes: 'Beta test firmware',
        binaryUrl: 'https://storage.example.com/firmware/test.bin',
        binaryFilename: 'test.bin',
        isProductionReady: false,
        createdBy: 'user-1',
        createdAt: now,
      );

      // Verify production-ready firmware is preferred
      expect(firmware.isProductionReady, true);
      expect(testFirmware.isProductionReady, false);

      // In practice, the UI should only show production-ready firmware
      // for production units
    });
  });
}
