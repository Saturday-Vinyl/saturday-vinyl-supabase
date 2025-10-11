import 'dart:io';
import 'dart:typed_data';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:path/path.dart' as path;

/// Service for managing file uploads to Supabase Storage
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String productionFilesBucket = 'production-files';
  static const String qrCodesBucket = 'qr-codes';
  static const String firmwareBucket = 'firmware-binaries';

  static const int maxFileSizeMB = 50;
  static const int maxFileSizeBytes = maxFileSizeMB * 1024 * 1024;

  /// Upload a production step file to Supabase storage
  /// Returns the public URL of the uploaded file
  Future<String> uploadProductionFile(
    File file,
    String productId,
    String stepId,
  ) async {
    try {
      // Validate file size
      final fileSize = await file.length();
      if (fileSize > maxFileSizeBytes) {
        throw Exception(
          'File size (${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB) exceeds maximum allowed size (${maxFileSizeMB}MB)',
        );
      }

      // Generate unique file name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(file.path);
      final fileName = '$stepId-$timestamp$extension';
      final filePath = '$productId/$fileName';

      AppLogger.info('Uploading production file: $filePath (${(fileSize / 1024).toStringAsFixed(1)}KB)');

      // Upload to Supabase storage with retry logic
      await _uploadWithRetry(
        file,
        productionFilesBucket,
        filePath,
        maxRetries: 3,
      );

      // Get file path (production-files is a private bucket)
      // Note: We store the file path in the database, not a signed URL
      // Signed URLs should be generated on-demand when needed for access
      final fileUrl = 'storage/v1/object/$productionFilesBucket/$filePath';

      AppLogger.info('Production file uploaded successfully: $fileUrl');
      return fileUrl;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upload production file', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a production file from storage
  Future<void> deleteProductionFile(String fileUrl) async {
    try {
      final filePath = _extractPathFromUrl(fileUrl, productionFilesBucket);
      if (filePath == null) {
        throw Exception('Invalid file URL: $fileUrl');
      }

      AppLogger.info('Deleting production file: $filePath');

      final supabase = SupabaseService.instance.client;
      await supabase.storage
          .from(productionFilesBucket)
          .remove([filePath]);

      AppLogger.info('Production file deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete production file', error, stackTrace);
      rethrow;
    }
  }

  /// Upload QR code image to private bucket
  /// Returns the file path (not a signed URL - generate signed URL on-demand)
  Future<String> uploadQRCode(Uint8List imageData, String uuid) async {
    try {
      final fileName = '$uuid.png';
      final filePath = 'qr-codes/$fileName';

      AppLogger.info('Uploading QR code: $filePath');

      final supabase = SupabaseService.instance.client;
      await supabase.storage
          .from(qrCodesBucket)
          .uploadBinary(filePath, imageData);

      // Return file path (qr-codes is a private bucket)
      final fileUrl = 'storage/v1/object/$qrCodesBucket/$filePath';

      AppLogger.info('QR code uploaded successfully: $fileUrl');
      return fileUrl;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upload QR code', error, stackTrace);
      rethrow;
    }
  }

  /// Upload firmware binary file
  /// Returns the public URL
  Future<String> uploadFirmwareBinary(
    File file,
    String deviceTypeId,
    String version,
  ) async {
    try {
      // Validate file size
      final fileSize = await file.length();
      if (fileSize > maxFileSizeBytes) {
        throw Exception(
          'File size exceeds maximum allowed size (${maxFileSizeMB}MB)',
        );
      }

      // Generate file name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(file.path);
      final fileName = '$deviceTypeId-$version-$timestamp$extension';

      AppLogger.info('Uploading firmware binary: $fileName');

      final supabase = SupabaseService.instance.client;
      await _uploadWithRetry(
        file,
        firmwareBucket,
        fileName,
        maxRetries: 3,
      );

      final publicUrl = supabase.storage
          .from(firmwareBucket)
          .getPublicUrl(fileName);

      AppLogger.info('Firmware binary uploaded successfully: $publicUrl');
      return publicUrl;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upload firmware binary', error, stackTrace);
      rethrow;
    }
  }

  /// Delete firmware binary from storage
  Future<void> deleteFirmwareBinary(String fileUrl) async {
    try {
      final filePath = _extractPathFromUrl(fileUrl, firmwareBucket);
      if (filePath == null) {
        throw Exception('Invalid firmware URL: $fileUrl');
      }

      AppLogger.info('Deleting firmware binary: $filePath');

      final supabase = SupabaseService.instance.client;
      await supabase.storage
          .from(firmwareBucket)
          .remove([filePath]);

      AppLogger.info('Firmware binary deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete firmware binary', error, stackTrace);
      rethrow;
    }
  }

  /// Download file from URL to local path
  Future<File> downloadFile(String fileUrl, String localPath) async {
    try {
      AppLogger.info('Downloading file from: $fileUrl');

      final supabase = SupabaseService.instance.client;

      // Extract bucket and path from URL
      final uri = Uri.parse(fileUrl);
      final pathSegments = uri.pathSegments;

      if (pathSegments.length < 3) {
        throw Exception('Invalid file URL format');
      }

      final bucket = pathSegments[2];
      final filePath = pathSegments.skip(3).join('/');

      final bytes = await supabase.storage
          .from(bucket)
          .download(filePath);

      final file = File(localPath);
      await file.writeAsBytes(bytes);

      AppLogger.info('File downloaded successfully to: $localPath');
      return file;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to download file', error, stackTrace);
      rethrow;
    }
  }

  /// Upload file with retry logic
  Future<void> _uploadWithRetry(
    File file,
    String bucket,
    String filePath, {
    int maxRetries = 3,
  }) async {
    int retryCount = 0;

    while (true) {
      try {
        final supabase = SupabaseService.instance.client;
        await supabase.storage
            .from(bucket)
            .upload(filePath, file);
        return;
      } catch (error) {
        if (retryCount < maxRetries) {
          retryCount++;
          final delay = Duration(seconds: retryCount * 2);
          AppLogger.warning(
            'Upload retry $retryCount/$maxRetries after error: $error. Waiting ${delay.inSeconds}s',
          );
          await Future.delayed(delay);
        } else {
          rethrow;
        }
      }
    }
  }

  /// Extract file path from Supabase public URL
  String? _extractPathFromUrl(String url, String bucket) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // URL format: .../storage/v1/object/public/{bucket}/{path}
      final bucketIndex = pathSegments.indexOf(bucket);
      if (bucketIndex == -1 || bucketIndex >= pathSegments.length - 1) {
        return null;
      }

      return pathSegments.skip(bucketIndex + 1).join('/');
    } catch (e) {
      return null;
    }
  }

  /// Generate a signed URL for accessing a private file
  ///
  /// Use this for production-files and qr-codes buckets which are private.
  /// Signed URLs expire after the specified duration (default: 1 hour).
  ///
  /// Example usage:
  /// ```dart
  /// final signedUrl = await storageService.getSignedUrl(
  ///   'storage/v1/object/production-files/product-123/step-456.pdf',
  ///   expiresIn: Duration(hours: 2),
  /// );
  /// ```
  Future<String> getSignedUrl(
    String fileUrl, {
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    try {
      // Extract bucket and path from stored URL
      final parts = fileUrl.split('/');
      if (parts.length < 4) {
        throw Exception('Invalid file URL format');
      }

      final bucketIndex = parts.indexOf('object') + 1;
      final bucket = parts[bucketIndex];
      final filePath = parts.skip(bucketIndex + 1).join('/');

      AppLogger.info('Generating signed URL for: $bucket/$filePath');

      final supabase = SupabaseService.instance.client;
      final signedUrl = await supabase.storage
          .from(bucket)
          .createSignedUrl(filePath, expiresIn.inSeconds);

      return signedUrl;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to generate signed URL', error, stackTrace);
      rethrow;
    }
  }

  /// Get file size in human-readable format
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }
}
