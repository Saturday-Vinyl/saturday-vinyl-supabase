import 'dart:typed_data';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Service for managing file library uploads to Supabase Storage
class FileStorageService {
  static final FileStorageService _instance = FileStorageService._internal();
  factory FileStorageService() => _instance;
  FileStorageService._internal();

  static const String filesBucket = 'files';
  static const int maxFileSizeMB = 50;
  static const int maxFileSizeBytes = maxFileSizeMB * 1024 * 1024; // 52428800 bytes

  final _uuid = const Uuid();

  /// Upload a file to the files library bucket
  /// Returns the storage path (e.g., "files/abc-123.gcode")
  Future<String> uploadFile(
    Uint8List fileBytes,
    String fileName,
    String mimeType,
  ) async {
    try {
      // Validate file size
      if (fileBytes.length > maxFileSizeBytes) {
        throw Exception(
          'File size (${(fileBytes.length / 1024 / 1024).toStringAsFixed(1)}MB) '
          'exceeds maximum allowed size (${maxFileSizeMB}MB)',
        );
      }

      // Generate unique storage path with UUID and original extension
      final fileExtension = _getFileExtension(fileName);
      final uniqueId = _uuid.v4();
      final storagePath = '$uniqueId$fileExtension';

      AppLogger.info(
        'Uploading file: $fileName → $storagePath '
        '(${(fileBytes.length / 1024).toStringAsFixed(1)}KB)',
      );

      // Upload to Supabase storage
      final supabase = SupabaseService.instance.client;
      await supabase.storage
          .from(filesBucket)
          .uploadBinary(storagePath, fileBytes);

      AppLogger.info('File uploaded successfully: $storagePath');
      return storagePath;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upload file', error, stackTrace);
      rethrow;
    }
  }

  /// Download a file from the files library bucket
  /// Returns the file bytes
  Future<Uint8List> downloadFile(String storagePath) async {
    try {
      AppLogger.info('Downloading file: $storagePath');

      final supabase = SupabaseService.instance.client;
      final bytes = await supabase.storage
          .from(filesBucket)
          .download(storagePath);

      AppLogger.info(
        'File downloaded successfully: $storagePath '
        '(${(bytes.length / 1024).toStringAsFixed(1)}KB)',
      );
      return bytes;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to download file', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a file from the files library bucket
  Future<void> deleteFile(String storagePath) async {
    try {
      AppLogger.info('Deleting file: $storagePath');

      final supabase = SupabaseService.instance.client;
      await supabase.storage
          .from(filesBucket)
          .remove([storagePath]);

      AppLogger.info('File deleted successfully: $storagePath');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete file', error, stackTrace);
      rethrow;
    }
  }

  /// Get a signed URL for downloading a file (valid for 1 hour)
  /// Use this for temporary access to private files
  Future<String> getSignedUrl(String storagePath) async {
    try {
      final supabase = SupabaseService.instance.client;
      final signedUrl = await supabase.storage
          .from(filesBucket)
          .createSignedUrl(storagePath, 3600); // 1 hour

      return signedUrl;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to generate signed URL', error, stackTrace);
      rethrow;
    }
  }

  /// Extract file extension from filename (including the dot)
  String _getFileExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) {
      return ''; // No extension
    }
    return fileName.substring(lastDot).toLowerCase();
  }

  /// Validate file size before upload
  bool validateFileSize(int fileSizeBytes) {
    return fileSizeBytes > 0 && fileSizeBytes <= maxFileSizeBytes;
  }
}
