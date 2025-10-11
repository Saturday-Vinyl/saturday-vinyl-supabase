import 'dart:io';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing firmware versions
class FirmwareRepository {
  static const String _tableName = 'firmware_versions';

  /// Get all firmware versions, optionally filtered by device type
  Future<List<FirmwareVersion>> getFirmwareVersions({String? deviceTypeId}) async {
    try {
      AppLogger.info('Fetching firmware versions${deviceTypeId != null ? " for device type: $deviceTypeId" : ""}');

      final supabase = SupabaseService.instance.client;

      final response = deviceTypeId != null
          ? await supabase
              .from(_tableName)
              .select()
              .eq('device_type_id', deviceTypeId)
              .order('created_at', ascending: false)
          : await supabase
              .from(_tableName)
              .select()
              .order('created_at', ascending: false);

      final List<dynamic> data = response as List<dynamic>;

      final firmware = data
          .map((json) => FirmwareVersion.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Fetched ${firmware.length} firmware versions');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch firmware versions', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single firmware version by ID
  Future<FirmwareVersion?> getFirmwareVersion(String id) async {
    try {
      AppLogger.info('Fetching firmware version: $id');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_tableName)
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('Firmware version not found: $id');
        return null;
      }

      final firmware = FirmwareVersion.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Fetched firmware version: ${firmware.version}');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch firmware version', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new firmware version with binary upload
  ///
  /// This performs a two-step process:
  /// 1. Upload the binary file to storage
  /// 2. Create the firmware version record in the database
  ///
  /// If either step fails, the other is rolled back
  Future<FirmwareVersion> createFirmwareVersion(
    FirmwareVersion firmware,
    File binaryFile,
  ) async {
    String? uploadedFileUrl;

    try {
      AppLogger.info('Creating firmware version: ${firmware.version}');

      // Step 1: Upload binary file
      final storageService = StorageService();
      uploadedFileUrl = await storageService.uploadFirmwareBinary(
        binaryFile,
        firmware.deviceTypeId,
        firmware.version,
      );

      AppLogger.info('Binary uploaded successfully: $uploadedFileUrl');

      // Step 2: Create database record with uploaded file URL and size
      final fileSize = await binaryFile.length();
      final firmwareWithUrl = firmware.copyWith(
        binaryUrl: uploadedFileUrl,
        binarySize: fileSize,
      );

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_tableName)
          .insert(firmwareWithUrl.toInsertJson())
          .select()
          .single();

      final created = FirmwareVersion.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Firmware version created successfully: ${created.id}');
      return created;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create firmware version', error, stackTrace);

      // Rollback: Delete uploaded file if database insert failed
      if (uploadedFileUrl != null) {
        try {
          AppLogger.info('Rolling back: Deleting uploaded file');
          final storageService = StorageService();
          await storageService.deleteFirmwareBinary(uploadedFileUrl);
        } catch (deleteError) {
          AppLogger.error('Failed to rollback file upload', deleteError);
        }
      }

      rethrow;
    }
  }

  /// Update firmware version metadata (not the binary)
  Future<FirmwareVersion> updateFirmwareVersion(FirmwareVersion firmware) async {
    try {
      AppLogger.info('Updating firmware version: ${firmware.id}');

      final supabase = SupabaseService.instance.client;

      // Only update metadata fields, not the binary URL
      final updateData = {
        'version': firmware.version,
        'release_notes': firmware.releaseNotes,
        'is_production_ready': firmware.isProductionReady,
      };

      final response = await supabase
          .from(_tableName)
          .update(updateData)
          .eq('id', firmware.id)
          .select()
          .single();

      final updated = FirmwareVersion.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Firmware version updated successfully');
      return updated;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update firmware version', error, stackTrace);
      rethrow;
    }
  }

  /// Delete firmware version and its binary file
  Future<void> deleteFirmwareVersion(String id) async {
    try {
      AppLogger.info('Deleting firmware version: $id');

      // Get the firmware to retrieve the binary URL
      final firmware = await getFirmwareVersion(id);
      if (firmware == null) {
        throw Exception('Firmware version not found: $id');
      }

      // Delete from database first
      final supabase = SupabaseService.instance.client;
      await supabase.from(_tableName).delete().eq('id', id);

      // Then delete the binary file
      final storageService = StorageService();
      await storageService.deleteFirmwareBinary(firmware.binaryUrl);

      AppLogger.info('Firmware version deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete firmware version', error, stackTrace);
      rethrow;
    }
  }

  /// Mark firmware version as production ready (or not)
  Future<FirmwareVersion> markAsProductionReady(String id, bool isReady) async {
    try {
      AppLogger.info('Marking firmware version $id as production ready: $isReady');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_tableName)
          .update({'is_production_ready': isReady})
          .eq('id', id)
          .select()
          .single();

      final updated = FirmwareVersion.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Firmware version production status updated');
      return updated;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update production status', error, stackTrace);
      rethrow;
    }
  }

  /// Get the latest production-ready firmware for a device type
  Future<FirmwareVersion?> getLatestProductionFirmware(String deviceTypeId) async {
    try {
      AppLogger.info('Fetching latest production firmware for device type: $deviceTypeId');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_tableName)
          .select()
          .eq('device_type_id', deviceTypeId)
          .eq('is_production_ready', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No production firmware found for device type');
        return null;
      }

      final firmware = FirmwareVersion.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Found production firmware: ${firmware.version}');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch latest production firmware', error, stackTrace);
      rethrow;
    }
  }
}
