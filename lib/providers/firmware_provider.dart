import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/firmware.dart';
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

// ============================================================================
// New Firmware Providers (with multi-SoC support)
// ============================================================================

/// Provider for all firmware entries (new table)
final allFirmwareProvider = FutureProvider<List<Firmware>>((ref) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return repository.getAllFirmware();
});

/// Provider for firmware by device type (new table)
final firmwareByDeviceTypeProvider =
    FutureProvider.family<List<Firmware>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return repository.getAllFirmware(deviceTypeId: deviceTypeId);
});

/// Provider for a single firmware by ID (new table)
final firmwareByIdProvider =
    FutureProvider.family<Firmware?, String>((ref, id) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return repository.getFirmwareById(id);
});

/// Provider for latest released firmware for a device type
final latestReleasedFirmwareProvider =
    FutureProvider.family<Firmware?, String>((ref, deviceTypeId) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return repository.getLatestReleasedFirmware(deviceTypeId);
});

/// Provider for latest development (unreleased) firmware for a device type
final latestDevFirmwareProvider =
    FutureProvider.family<Firmware?, String>((ref, deviceTypeId) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return repository.getLatestDevFirmware(deviceTypeId);
});

/// Provider for critical firmware updates for a device type
final criticalFirmwareProvider =
    FutureProvider.family<List<Firmware>, String>((ref, deviceTypeId) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return repository.getCriticalFirmware(deviceTypeId);
});

/// Provider for firmware file by SoC type
final firmwareFileForSocProvider = FutureProvider.family<FirmwareFile?,
    ({String firmwareId, String socType})>((ref, params) async {
  final repository = ref.watch(firmwareRepositoryProvider);
  return repository.getFirmwareFileForSoc(params.firmwareId, params.socType);
});

/// Extended firmware management with multi-SoC support
extension FirmwareManagementExtensions on FirmwareManagement {
  /// Create a new firmware with files (multi-SoC)
  Future<Firmware> createFirmwareWithFiles(
    Firmware firmware,
    List<FirmwareFileUpload> fileUploads,
  ) async {
    try {
      AppLogger.info('Creating firmware: ${firmware.version}');

      final repository = ref.read(firmwareRepositoryProvider);
      final created = await repository.createFirmware(firmware, fileUploads);

      // Invalidate providers
      ref.invalidate(allFirmwareProvider);
      ref.invalidate(firmwareByDeviceTypeProvider(firmware.deviceTypeId));
      ref.invalidate(latestReleasedFirmwareProvider(firmware.deviceTypeId));

      AppLogger.info('Firmware created successfully: ${created.id}');
      return created;
    } catch (error, stackTrace) {
      AppLogger.error('Error creating firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Add a file to existing firmware
  Future<FirmwareFile> addFirmwareFile({
    required String firmwareId,
    required String socType,
    required bool isMaster,
    required File file,
    String? sha256,
  }) async {
    try {
      AppLogger.info('Adding firmware file for $socType');

      final repository = ref.read(firmwareRepositoryProvider);
      final firmwareFile = await repository.addFirmwareFile(
        firmwareId: firmwareId,
        socType: socType,
        isMaster: isMaster,
        file: file,
        sha256: sha256,
      );

      // Invalidate providers
      ref.invalidate(firmwareByIdProvider(firmwareId));
      ref.invalidate(
        firmwareFileForSocProvider((firmwareId: firmwareId, socType: socType)),
      );

      AppLogger.info('Firmware file added successfully');
      return firmwareFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error adding firmware file', error, stackTrace);
      rethrow;
    }
  }

  /// Release a firmware (set released_at timestamp)
  Future<Firmware> releaseFirmware(String firmwareId) async {
    try {
      AppLogger.info('Releasing firmware: $firmwareId');

      final repository = ref.read(firmwareRepositoryProvider);
      final firmware = await repository.releaseFirmware(firmwareId);

      // Invalidate providers
      ref.invalidate(firmwareByIdProvider(firmwareId));
      ref.invalidate(allFirmwareProvider);
      ref.invalidate(firmwareByDeviceTypeProvider(firmware.deviceTypeId));
      ref.invalidate(latestReleasedFirmwareProvider(firmware.deviceTypeId));

      AppLogger.info('Firmware released successfully');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Error releasing firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Mark firmware as critical
  Future<Firmware> markFirmwareAsCritical(
    String firmwareId,
    bool isCritical,
  ) async {
    try {
      AppLogger.info('Marking firmware $firmwareId as critical: $isCritical');

      final repository = ref.read(firmwareRepositoryProvider);
      final firmware = await repository.markAsCritical(firmwareId, isCritical);

      // Invalidate providers
      ref.invalidate(firmwareByIdProvider(firmwareId));
      ref.invalidate(criticalFirmwareProvider(firmware.deviceTypeId));

      AppLogger.info('Firmware critical status updated');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating firmware critical status', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a firmware (new table)
  Future<void> deleteNewFirmware(String firmwareId) async {
    try {
      AppLogger.info('Deleting firmware: $firmwareId');

      final repository = ref.read(firmwareRepositoryProvider);
      final firmware = await repository.getFirmwareById(firmwareId);

      await repository.deleteFirmware(firmwareId);

      // Invalidate providers
      ref.invalidate(allFirmwareProvider);
      if (firmware != null) {
        ref.invalidate(firmwareByDeviceTypeProvider(firmware.deviceTypeId));
        ref.invalidate(latestReleasedFirmwareProvider(firmware.deviceTypeId));
        ref.invalidate(criticalFirmwareProvider(firmware.deviceTypeId));
      }

      AppLogger.info('Firmware deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Download a firmware file
  Future<File> downloadFirmwareFile(FirmwareFile firmwareFile) async {
    try {
      AppLogger.info('Downloading firmware file: ${firmwareFile.filename}');

      final repository = ref.read(firmwareRepositoryProvider);
      final file = await repository.downloadFirmwareFile(firmwareFile);

      AppLogger.info('Firmware file downloaded: ${file.path}');
      return file;
    } catch (error, stackTrace) {
      AppLogger.error('Error downloading firmware file', error, stackTrace);
      rethrow;
    }
  }
}
