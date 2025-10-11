import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/services/storage_service.dart';

void main() {
  group('StorageService', () {
    test('should be a singleton', () {
      final instance1 = StorageService();
      final instance2 = StorageService();

      expect(instance1, same(instance2));
    });

    test('formatFileSize should format bytes correctly', () {
      expect(StorageService.formatFileSize(500), '500 B');
      expect(StorageService.formatFileSize(1024), '1.0 KB');
      expect(StorageService.formatFileSize(1536), '1.5 KB');
      expect(StorageService.formatFileSize(1024 * 1024), '1.0 MB');
      expect(StorageService.formatFileSize(1024 * 1024 * 2), '2.0 MB');
      expect(StorageService.formatFileSize(1024 * 1024 + 512 * 1024), '1.5 MB');
    });

    test('should have correct bucket names', () {
      expect(StorageService.productionFilesBucket, 'production-files');
      expect(StorageService.qrCodesBucket, 'qr-codes');
      expect(StorageService.firmwareBucket, 'firmware-binaries');
    });

    test('should have correct file size limits', () {
      expect(StorageService.maxFileSizeMB, 50);
      expect(StorageService.maxFileSizeBytes, 50 * 1024 * 1024);
    });
  });
}
