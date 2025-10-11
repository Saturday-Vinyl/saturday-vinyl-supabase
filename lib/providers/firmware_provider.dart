import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/repositories/firmware_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for FirmwareRepository
final firmwareRepositoryProvider = Provider<FirmwareRepository>((ref) {
  return FirmwareRepository();
});

/// Provider for all firmware versions
final firmwareVersionsProvider =
    FutureProvider<List<FirmwareVersion>>((ref) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return await repository.getFirmwareVersions();
});

/// Provider for firmware versions filtered by device type (family provider)
final firmwareVersionsByDeviceTypeProvider =
    FutureProvider.family<List<FirmwareVersion>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return await repository.getFirmwareVersions(deviceTypeId: deviceTypeId);
});

/// Provider for a single firmware version by ID (family provider)
final firmwareVersionProvider =
    FutureProvider.family<FirmwareVersion?, String>((ref, id) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return await repository.getFirmwareVersion(id);
});

/// Provider for latest production firmware for a device type (family provider)
final latestProductionFirmwareProvider =
    FutureProvider.family<FirmwareVersion?, String>((ref, deviceTypeId) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return await repository.getLatestProductionFirmware(deviceTypeId);
});

/// Provider for firmware management actions
final firmwareManagementProvider =
    Provider((ref) => FirmwareManagement(ref));

/// Firmware management actions
class FirmwareManagement {
  final Ref ref;

  FirmwareManagement(this.ref);

  /// Upload a new firmware version
  Future<FirmwareVersion> uploadFirmware(
    FirmwareVersion firmware,
    File binaryFile,
  ) async {
    try {
      AppLogger.info('Uploading firmware version: ${firmware.version}');

      final repository = ref.read(firmwareRepositoryProvider);
      final newFirmware = await repository.createFirmwareVersion(
        firmware,
        binaryFile,
      );

      // Invalidate providers to refresh
      ref.invalidate(firmwareVersionsProvider);
      ref.invalidate(firmwareVersionsByDeviceTypeProvider(firmware.deviceTypeId));
      ref.invalidate(latestProductionFirmwareProvider(firmware.deviceTypeId));

      AppLogger.info('Firmware uploaded successfully: ${newFirmware.id}');
      return newFirmware;
    } catch (error, stackTrace) {
      AppLogger.error('Error uploading firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Update firmware version metadata
  Future<void> updateFirmware(FirmwareVersion firmware) async {
    try {
      AppLogger.info('Updating firmware version: ${firmware.id}');

      final repository = ref.read(firmwareRepositoryProvider);
      await repository.updateFirmwareVersion(firmware);

      // Invalidate providers to refresh
      ref.invalidate(firmwareVersionsProvider);
      ref.invalidate(firmwareVersionProvider(firmware.id));
      ref.invalidate(firmwareVersionsByDeviceTypeProvider(firmware.deviceTypeId));
      ref.invalidate(latestProductionFirmwareProvider(firmware.deviceTypeId));

      AppLogger.info('Firmware updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Error updating firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a firmware version
  Future<void> deleteFirmware(String firmwareId) async {
    try {
      AppLogger.info('Deleting firmware version: $firmwareId');

      // Get the firmware first to know which device type to invalidate
      final repository = ref.read(firmwareRepositoryProvider);
      final firmware = await repository.getFirmwareVersion(firmwareId);

      await repository.deleteFirmwareVersion(firmwareId);

      // Invalidate providers to refresh
      ref.invalidate(firmwareVersionsProvider);
      if (firmware != null) {
        ref.invalidate(firmwareVersionsByDeviceTypeProvider(firmware.deviceTypeId));
        ref.invalidate(latestProductionFirmwareProvider(firmware.deviceTypeId));
      }

      AppLogger.info('Firmware deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Toggle production ready status
  Future<void> toggleProductionReady(String firmwareId, bool isReady) async {
    try {
      AppLogger.info(
        'Setting firmware $firmwareId production ready: $isReady',
      );

      final repository = ref.read(firmwareRepositoryProvider);
      await repository.markAsProductionReady(firmwareId, isReady);

      // Get firmware to know which device type to invalidate
      final firmware = await repository.getFirmwareVersion(firmwareId);

      // Invalidate providers to refresh
      ref.invalidate(firmwareVersionsProvider);
      ref.invalidate(firmwareVersionProvider(firmwareId));
      if (firmware != null) {
        ref.invalidate(firmwareVersionsByDeviceTypeProvider(firmware.deviceTypeId));
        ref.invalidate(latestProductionFirmwareProvider(firmware.deviceTypeId));
      }

      AppLogger.info('Firmware production status updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Error updating firmware status', error, stackTrace);
      rethrow;
    }
  }
}
