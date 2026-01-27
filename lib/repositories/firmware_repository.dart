import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:saturday_app/models/firmware.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:http/http.dart' as http;

/// Repository for managing firmware versions
///
/// Uses the firmware table (renamed from firmware_versions) with
/// multi-SoC support via firmware_files.
class FirmwareRepository {
  static const String _tableName = 'firmware';  // Renamed from firmware_versions
  static const String _newTableName = 'firmware';
  static const String _filesTableName = 'firmware_files';

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

  /// Download firmware binary to a temporary directory
  ///
  /// Returns the local file path to the downloaded binary
  Future<File> downloadFirmwareBinary(String firmwareId) async {
    try {
      AppLogger.info('Downloading firmware binary: $firmwareId');

      // Get firmware version to get the binary URL
      final firmware = await getFirmwareVersion(firmwareId);
      if (firmware == null) {
        throw Exception('Firmware version not found: $firmwareId');
      }

      // Download the file
      final response = await http.get(Uri.parse(firmware.binaryUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download firmware: HTTP ${response.statusCode}');
      }

      // Save to temp directory
      final tempDir = await getTemporaryDirectory();
      final localPath = '${tempDir.path}/firmware_${firmwareId}_${firmware.binaryFilename}';
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);

      AppLogger.info('Firmware downloaded to: $localPath');
      return file;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to download firmware binary', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // New Firmware Table Methods (with multi-SoC support)
  // ============================================================================

  /// Get all firmware entries with their files
  Future<List<Firmware>> getAllFirmware({String? deviceTypeId}) async {
    try {
      AppLogger.info('Fetching firmware${deviceTypeId != null ? " for device type: $deviceTypeId" : ""}');

      final supabase = SupabaseService.instance.client;

      var query = supabase.from(_newTableName).select('''
        *,
        firmware_files (*)
      ''');

      if (deviceTypeId != null) {
        query = query.eq('device_type_id', deviceTypeId);
      }

      final response = await query.order('created_at', ascending: false);

      final firmware = (response as List)
          .map((json) => Firmware.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Fetched ${firmware.length} firmware entries');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single firmware by ID with its files
  Future<Firmware?> getFirmwareById(String id) async {
    try {
      AppLogger.info('Fetching firmware: $id');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_newTableName)
          .select('''
            *,
            firmware_files (*)
          ''')
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('Firmware not found: $id');
        return null;
      }

      final firmware = Firmware.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Fetched firmware: ${firmware.version}');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Get the latest released firmware for a device type
  Future<Firmware?> getLatestReleasedFirmware(String deviceTypeId) async {
    try {
      AppLogger.info('Fetching latest released firmware for device type: $deviceTypeId');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_newTableName)
          .select('''
            *,
            firmware_files (*)
          ''')
          .eq('device_type_id', deviceTypeId)
          .not('released_at', 'is', null)
          .order('released_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No released firmware found for device type');
        return null;
      }

      final firmware = Firmware.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Found released firmware: ${firmware.version}');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch latest released firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Get critical firmware updates for a device type
  Future<List<Firmware>> getCriticalFirmware(String deviceTypeId) async {
    try {
      AppLogger.info('Fetching critical firmware for device type: $deviceTypeId');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_newTableName)
          .select('''
            *,
            firmware_files (*)
          ''')
          .eq('device_type_id', deviceTypeId)
          .eq('is_critical', true)
          .not('released_at', 'is', null)
          .order('released_at', ascending: false);

      final firmware = (response as List)
          .map((json) => Firmware.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Found ${firmware.length} critical firmware updates');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch critical firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new firmware with files
  Future<Firmware> createFirmware(
    Firmware firmware,
    List<FirmwareFileUpload> fileUploads,
  ) async {
    try {
      AppLogger.info('Creating firmware: ${firmware.version}');

      final supabase = SupabaseService.instance.client;
      final storageService = StorageService();

      // Step 1: Create firmware record
      final response = await supabase
          .from(_newTableName)
          .insert(firmware.toInsertJson())
          .select()
          .single();

      final createdFirmware = Firmware.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Firmware created: ${createdFirmware.id}');

      // Step 2: Upload files and create firmware_files records
      final files = <FirmwareFile>[];
      for (final upload in fileUploads) {
        final fileUrl = await storageService.uploadFirmwareBinary(
          upload.file,
          firmware.deviceTypeId,
          '${firmware.version}_${upload.socType}',
        );

        final fileSize = await upload.file.length();
        final fileData = {
          'firmware_id': createdFirmware.id,
          'soc_type': upload.socType,
          'is_master': upload.isMaster,
          'file_url': fileUrl,
          'file_sha256': upload.sha256,
          'file_size': fileSize,
        };

        final fileResponse = await supabase
            .from(_filesTableName)
            .insert(fileData)
            .select()
            .single();

        files.add(FirmwareFile.fromJson(fileResponse));
      }

      AppLogger.info('Created ${files.length} firmware files');

      return createdFirmware.copyWith(files: files);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create firmware', error, stackTrace);
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
      AppLogger.info('Adding firmware file for $socType to firmware $firmwareId');

      final firmware = await getFirmwareById(firmwareId);
      if (firmware == null) {
        throw Exception('Firmware not found: $firmwareId');
      }

      final storageService = StorageService();
      final fileUrl = await storageService.uploadFirmwareBinary(
        file,
        firmware.deviceTypeId,
        '${firmware.version}_$socType',
      );

      final fileSize = await file.length();
      final supabase = SupabaseService.instance.client;

      final response = await supabase
          .from(_filesTableName)
          .insert({
            'firmware_id': firmwareId,
            'soc_type': socType,
            'is_master': isMaster,
            'file_url': fileUrl,
            'file_sha256': sha256,
            'file_size': fileSize,
          })
          .select()
          .single();

      final firmwareFile = FirmwareFile.fromJson(response);
      AppLogger.info('Firmware file added: ${firmwareFile.id}');
      return firmwareFile;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to add firmware file', error, stackTrace);
      rethrow;
    }
  }

  /// Get firmware file for a specific SoC type
  Future<FirmwareFile?> getFirmwareFileForSoc(
    String firmwareId,
    String socType,
  ) async {
    try {
      AppLogger.info('Fetching firmware file for $socType in firmware $firmwareId');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_filesTableName)
          .select()
          .eq('firmware_id', firmwareId)
          .eq('soc_type', socType)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('No firmware file found for $socType');
        return null;
      }

      final file = FirmwareFile.fromJson(response);
      AppLogger.info('Found firmware file: ${file.filename}');
      return file;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch firmware file for SoC', error, stackTrace);
      rethrow;
    }
  }

  /// Download a firmware file to temporary directory
  Future<File> downloadFirmwareFile(FirmwareFile firmwareFile) async {
    try {
      AppLogger.info('Downloading firmware file: ${firmwareFile.id}');

      final response = await http.get(Uri.parse(firmwareFile.fileUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download firmware file: HTTP ${response.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      final localPath = '${tempDir.path}/${firmwareFile.filename}';
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);

      AppLogger.info('Firmware file downloaded to: $localPath');
      return file;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to download firmware file', error, stackTrace);
      rethrow;
    }
  }

  /// Release a firmware (set released_at timestamp)
  Future<Firmware> releaseFirmware(String id) async {
    try {
      AppLogger.info('Releasing firmware: $id');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_newTableName)
          .update({
            'released_at': DateTime.now().toIso8601String(),
            'is_production_ready': true, // For backwards compatibility
          })
          .eq('id', id)
          .select('''
            *,
            firmware_files (*)
          ''')
          .single();

      final firmware = Firmware.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Firmware released: ${firmware.version}');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to release firmware', error, stackTrace);
      rethrow;
    }
  }

  /// Mark firmware as critical
  Future<Firmware> markAsCritical(String id, bool isCritical) async {
    try {
      AppLogger.info('Marking firmware $id as critical: $isCritical');

      final supabase = SupabaseService.instance.client;
      final response = await supabase
          .from(_newTableName)
          .update({'is_critical': isCritical})
          .eq('id', id)
          .select('''
            *,
            firmware_files (*)
          ''')
          .single();

      final firmware = Firmware.fromJson(response as Map<String, dynamic>);
      AppLogger.info('Firmware critical status updated');
      return firmware;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update critical status', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a firmware and all its files
  Future<void> deleteFirmware(String id) async {
    try {
      AppLogger.info('Deleting firmware: $id');

      final firmware = await getFirmwareById(id);
      if (firmware == null) {
        throw Exception('Firmware not found: $id');
      }

      final storageService = StorageService();

      // Delete files from storage
      for (final file in firmware.files) {
        try {
          await storageService.deleteFirmwareBinary(file.fileUrl);
        } catch (e) {
          AppLogger.warning('Failed to delete firmware file from storage: $e');
        }
      }

      // Delete legacy binary if present
      if (firmware.binaryUrl != null) {
        try {
          await storageService.deleteFirmwareBinary(firmware.binaryUrl!);
        } catch (e) {
          AppLogger.warning('Failed to delete legacy binary from storage: $e');
        }
      }

      // Delete from database (firmware_files cascade delete)
      final supabase = SupabaseService.instance.client;
      await supabase.from(_newTableName).delete().eq('id', id);

      AppLogger.info('Firmware deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete firmware', error, stackTrace);
      rethrow;
    }
  }
}

/// Helper class for firmware file uploads
class FirmwareFileUpload {
  final File file;
  final String socType;
  final bool isMaster;
  final String? sha256;

  const FirmwareFileUpload({
    required this.file,
    required this.socType,
    this.isMaster = false,
    this.sha256,
  });
}
