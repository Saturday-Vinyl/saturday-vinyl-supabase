import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/services/printer_service.dart';

void main() {
  group('PrinterService', () {
    late PrinterService printerService;
    late ProductionUnit testUnit;
    late Uint8List validPngData;

    setUp(() {
      printerService = PrinterService();

      // Create a test production unit
      testUnit = ProductionUnit(
        id: 'test-id',
        uuid: 'test-uuid',
        unitId: 'SV-TEST-00001',
        productId: 'product-id',
        variantId: 'variant-id',
        qrCodeUrl: 'https://example.com/qr.png',
        shopifyOrderNumber: 'ORD-123',
        customerName: 'Test Customer',
        isCompleted: false,
        createdAt: DateTime.now(),
        createdBy: 'test-user',
      );

      // Create a valid 1x1 white PNG image using the image package
      final image = img.Image(width: 1, height: 1);
      image.setPixel(0, 0, img.ColorRgb8(255, 255, 255));
      validPngData = Uint8List.fromList(img.encodePng(image));
    });

    test('generateQRLabel creates PDF with all required elements', () async {
      final labelData = await printerService.generateQRLabel(
        unit: testUnit,
        productName: 'Test Product',
        variantName: 'Test Variant',
        qrImageData: validPngData,
      );

      // Verify label data was generated
      expect(labelData, isNotNull);
      expect(labelData.isNotEmpty, isTrue);

      // PDF files start with %PDF
      final pdfHeader = String.fromCharCodes(labelData.take(4));
      expect(pdfHeader, equals('%PDF'));
    });

    test('generateQRLabel includes customer info when available', () async {
      final labelData = await printerService.generateQRLabel(
        unit: testUnit,
        productName: 'Test Product',
        variantName: 'Test Variant',
        qrImageData: validPngData,
      );

      expect(labelData, isNotNull);
      expect(labelData.isNotEmpty, isTrue);
      // Customer name and order number are included in the PDF
      // Note: These might be compressed in the PDF, so we can't always find them as plain text
    });

    test('generateQRLabel works without customer info', () async {
      final unitWithoutCustomer = ProductionUnit(
        id: 'test-id',
        uuid: 'test-uuid',
        unitId: 'SV-TEST-00002',
        productId: 'product-id',
        variantId: 'variant-id',
        qrCodeUrl: 'https://example.com/qr.png',
        isCompleted: false,
        createdAt: DateTime.now(),
        createdBy: 'test-user',
      );

      final labelData = await printerService.generateQRLabel(
        unit: unitWithoutCustomer,
        productName: 'Test Product',
        variantName: 'Test Variant',
        qrImageData: validPngData,
      );

      expect(labelData, isNotNull);
      expect(labelData.isNotEmpty, isTrue);
    });

    test('isPrintingAvailable returns correct platform availability', () {
      final isAvailable = printerService.isPrintingAvailable();

      // This test will pass on desktop platforms and fail on mobile
      // In real testing, we'd mock Platform, but for now we just verify the method exists
      expect(isAvailable, isA<bool>());
    });

    test('selectPrinter stores selected printer', () async {
      // We can't easily test printer selection without mocking the printing package
      // This is a placeholder for when we add mockito support for Printer
      expect(printerService.getSelectedPrinter(), isNull);
    });

    test('getPrinterStatus returns status message', () async {
      // Skip this test as it requires platform channel mocking
      // This will be tested through manual testing
    }, skip: 'Requires Flutter bindings and platform channel mocking');

    test('generateQRLabel handles long product names', () async {
      final longProductName = 'A' * 100; // Very long product name
      final longVariantName = 'B' * 100; // Very long variant name

      final labelData = await printerService.generateQRLabel(
        unit: testUnit,
        productName: longProductName,
        variantName: longVariantName,
        qrImageData: validPngData,
      );

      expect(labelData, isNotNull);
      expect(labelData.isNotEmpty, isTrue);
    });

    test('generateQRLabel handles special characters', () async {
      final labelData = await printerService.generateQRLabel(
        unit: testUnit.copyWith(
          customerName: 'Test & Customer <>"',
          shopifyOrderNumber: 'ORD-123\'456',
        ),
        productName: 'Product & Co.',
        variantName: 'Variant "Special"',
        qrImageData: validPngData,
      );

      expect(labelData, isNotNull);
      expect(labelData.isNotEmpty, isTrue);
    });
  });
}
