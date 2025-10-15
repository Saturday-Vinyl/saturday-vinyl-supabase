import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:http/http.dart' as http;

/// Service for fetching QR code images from Supabase storage
class QRCodeFetchService {
  final SupabaseClient _supabase;
  final StorageService _storageService;

  QRCodeFetchService(this._supabase, [StorageService? storageService])
      : _storageService = storageService ?? StorageService();

  /// Fetch QR code PNG from Supabase storage
  ///
  /// Takes a Supabase storage URL and downloads the image bytes.
  /// For private buckets (like qr-codes), generates a signed URL first.
  ///
  /// Supports multiple URL formats:
  /// - https://{project}.supabase.co/storage/v1/object/public/{bucket}/{path}
  /// - storage/v1/object/{bucket}/{path}
  Future<Uint8List> fetchQRCodeImage(String qrCodeUrl) async {
    try {
      AppLogger.info('QR Code URL: $qrCodeUrl');

      // Extract bucket and path from URL
      final uri = Uri.parse(qrCodeUrl);
      final segments = uri.pathSegments;

      AppLogger.info('URL segments: ${segments.join(" / ")}');

      String bucket;
      String path;
      bool isPublic = false;

      // Try to find 'public' in segments (public bucket)
      final publicIndex = segments.indexOf('public');

      if (publicIndex != -1 && publicIndex < segments.length - 1) {
        // Format: .../object/public/{bucket}/{path}
        bucket = segments[publicIndex + 1];
        path = segments.sublist(publicIndex + 2).join('/');
        isPublic = true;
      } else {
        // Try to find 'object' in segments (non-public bucket or relative path)
        final objectIndex = segments.indexOf('object');

        if (objectIndex != -1 && objectIndex < segments.length - 1) {
          // Format: .../object/{bucket}/{path}
          bucket = segments[objectIndex + 1];
          path = segments.sublist(objectIndex + 2).join('/');
          isPublic = false;

          // Remove duplicate bucket name from path if present
          if (path.startsWith('$bucket/')) {
            path = path.substring(bucket.length + 1);
          }
        } else {
          throw Exception('Invalid storage URL format: $qrCodeUrl');
        }
      }

      AppLogger.info('Fetching QR code from bucket: $bucket, path: $path (public: $isPublic)');

      Uint8List bytes;

      if (isPublic) {
        // Public bucket - direct download
        bytes = await _supabase.storage.from(bucket).download(path);
      } else {
        // Private bucket - generate signed URL first
        AppLogger.info('Generating signed URL for private bucket access');
        final signedUrl = await _storageService.getSignedUrl(
          qrCodeUrl,
          expiresIn: const Duration(minutes: 5),
        );

        AppLogger.info('Downloading from signed URL');

        // Download using HTTP client (signed URL is a full HTTP URL)
        final response = await http.get(Uri.parse(signedUrl));

        if (response.statusCode != 200) {
          throw Exception('Failed to download QR code: HTTP ${response.statusCode}');
        }

        bytes = response.bodyBytes;
      }

      AppLogger.info('Downloaded ${bytes.length} bytes');

      return bytes;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch QR code image', e, stackTrace);
      rethrow;
    }
  }

  /// Fetch QR code image from bucket and path directly
  ///
  /// Alternative method if you already have the bucket and path separated.
  Future<Uint8List> fetchQRCodeImageFromPath({
    required String bucket,
    required String path,
  }) async {
    try {
      AppLogger.info('Fetching QR code from bucket: $bucket, path: $path');

      // Download from Supabase storage
      final bytes = await _supabase.storage.from(bucket).download(path);

      AppLogger.info('Downloaded ${bytes.length} bytes');

      return bytes;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to fetch QR code image', e, stackTrace);
      rethrow;
    }
  }
}
