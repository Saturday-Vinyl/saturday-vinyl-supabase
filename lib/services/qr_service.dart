import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saturday_app/config/env_config.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for generating and parsing QR codes for production units
class QRService {
  /// Load PNG logo and add white background for QR code visibility
  Future<ui.Image?> _loadLogoImage() async {
    try {
      const size = 180.0; // Final logo size in pixels (increased for better visibility)

      // Load PNG asset
      final ByteData data = await rootBundle.load(
        'assets/images/saturday-icon-qr-100x100.png',
      );
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image logoImage = frameInfo.image;

      // Create new image with white circular background
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw white circle background
      final backgroundPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        const Offset(size / 2, size / 2),
        size / 2,
        backgroundPaint,
      );

      // Draw logo on top, centered and scaled to fit
      final logoSize = size * 0.7; // Logo takes 70% of the circle
      final logoOffset = (size - logoSize) / 2;

      canvas.drawImageRect(
        logoImage,
        Rect.fromLTWH(0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
        Rect.fromLTWH(logoOffset, logoOffset, logoSize, logoSize),
        Paint(),
      );

      logoImage.dispose();

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      picture.dispose();

      return image;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load logo image', error, stackTrace);
      return null;
    }
  }

  /// Generate QR code with embedded logo
  /// Returns QR code as image data (Uint8List)
  Future<Uint8List> generateQRCode(
    String uuid, {
    int size = 512,
    bool embedLogo = true,
  }) async {
    try {
      final qrData = '${EnvConfig.appBaseUrl}/unit/$uuid';
      AppLogger.info('Generating QR code for: $qrData');

      // Load logo image if embedding is enabled
      ui.Image? logoImage;
      if (embedLogo) {
        logoImage = await _loadLogoImage();
        if (logoImage == null) {
          AppLogger.warning('Failed to load logo, generating QR code without it');
        }
      }

      // Create QR painter with high error correction for logo embedding
      final qrPainter = QrPainter(
        data: qrData,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H, // High correction for logo
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
        gapless: true,
        embeddedImage: logoImage,
        embeddedImageStyle: logoImage != null
            ? const QrEmbeddedImageStyle(
                size: Size(140, 140), // Increased from 80x80 to make logo more visible
              )
            : null,
      );

      // Convert to image
      final image = await qrPainter.toImage(size.toDouble());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      // Dispose logo image
      logoImage?.dispose();

      if (byteData == null) {
        throw Exception('Failed to convert QR code to image');
      }

      final bytes = byteData.buffer.asUint8List();
      AppLogger.info('QR code generated successfully (${bytes.length} bytes)');
      return bytes;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to generate QR code', error, stackTrace);
      rethrow;
    }
  }

  /// Parse QR code from scanned text
  /// Extracts UUID from URL format: {APP_BASE_URL}/unit/{uuid}
  /// Returns UUID or throws error if invalid
  String parseQRCode(String scannedText) {
    try {
      AppLogger.info('Parsing QR code: $scannedText');

      final uri = Uri.parse(scannedText);
      final expectedHost = Uri.parse(EnvConfig.appBaseUrl).host;

      // Validate host matches expected base URL
      if (uri.host != expectedHost) {
        throw FormatException(
          'Invalid QR code: wrong domain (expected $expectedHost, got ${uri.host})',
        );
      }

      // Parse path segments to extract UUID
      // Expected format: /unit/{uuid}
      final segments = uri.pathSegments;
      if (segments.length != 2 || segments[0] != 'unit') {
        throw FormatException(
          'Invalid QR code: wrong URL format (expected /unit/{uuid})',
        );
      }

      final uuid = segments[1];

      // Basic UUID validation (36 characters with hyphens)
      if (!_isValidUUID(uuid)) {
        throw FormatException('Invalid QR code: malformed UUID');
      }

      AppLogger.info('Successfully parsed UUID: $uuid');
      return uuid;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to parse QR code', error, stackTrace);
      rethrow;
    }
  }

  /// Validate UUID format
  bool _isValidUUID(String uuid) {
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidPattern.hasMatch(uuid);
  }
}
