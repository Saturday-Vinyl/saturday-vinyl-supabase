import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/printer_settings.dart';

void main() {
  group('PrinterSettings', () {
    test('creates default settings', () {
      const settings = PrinterSettings.defaultSettings();

      expect(settings.defaultPrinterId, isNull);
      expect(settings.defaultPrinterName, isNull);
      expect(settings.autoPrint, isFalse);
      expect(settings.labelWidth, equals(1.0));
      expect(settings.labelHeight, equals(1.0));
    });

    test('creates custom settings', () {
      const settings = PrinterSettings(
        defaultPrinterId: 'printer-123',
        defaultPrinterName: 'HP Printer',
        autoPrint: true,
        labelWidth: 2.0,
        labelHeight: 1.5,
      );

      expect(settings.defaultPrinterId, equals('printer-123'));
      expect(settings.defaultPrinterName, equals('HP Printer'));
      expect(settings.autoPrint, isTrue);
      expect(settings.labelWidth, equals(2.0));
      expect(settings.labelHeight, equals(1.5));
    });

    test('validates correct settings', () {
      const validSettings = PrinterSettings(
        labelWidth: 1.5,
        labelHeight: 2.0,
      );

      expect(validSettings.isValid(), isTrue);
    });

    test('rejects label size too small', () {
      const invalidSettings = PrinterSettings(
        labelWidth: 0.3,
        labelHeight: 1.0,
      );

      expect(invalidSettings.isValid(), isFalse);
    });

    test('rejects label size too large', () {
      const invalidSettings = PrinterSettings(
        labelWidth: 5.0,
        labelHeight: 1.0,
      );

      expect(invalidSettings.isValid(), isFalse);
    });

    test('checks if default printer is configured', () {
      const withPrinter = PrinterSettings(
        defaultPrinterId: 'printer-123',
        defaultPrinterName: 'Test Printer',
      );
      const withoutPrinter = PrinterSettings();

      expect(withPrinter.hasDefaultPrinter(), isTrue);
      expect(withoutPrinter.hasDefaultPrinter(), isFalse);
    });

    test('formats label size correctly', () {
      const settings = PrinterSettings(
        labelWidth: 2.0,
        labelHeight: 3.5,
      );

      expect(settings.getFormattedLabelSize(), equals('2.0" x 3.5"'));
    });

    test('copyWith creates new instance with updated fields', () {
      const original = PrinterSettings(
        defaultPrinterId: 'printer-1',
        autoPrint: false,
      );

      final updated = original.copyWith(
        autoPrint: true,
        labelWidth: 2.0,
      );

      expect(updated.defaultPrinterId, equals('printer-1')); // Unchanged
      expect(updated.autoPrint, isTrue); // Changed
      expect(updated.labelWidth, equals(2.0)); // Changed
      expect(updated.labelHeight, equals(1.0)); // Unchanged (default)
    });

    test('toJson serializes correctly', () {
      const settings = PrinterSettings(
        defaultPrinterId: 'printer-123',
        defaultPrinterName: 'Test Printer',
        autoPrint: true,
        labelWidth: 2.0,
        labelHeight: 1.5,
      );

      final json = settings.toJson();

      expect(json['default_printer_id'], equals('printer-123'));
      expect(json['default_printer_name'], equals('Test Printer'));
      expect(json['auto_print'], isTrue);
      expect(json['label_width'], equals(2.0));
      expect(json['label_height'], equals(1.5));
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'default_printer_id': 'printer-456',
        'default_printer_name': 'HP Printer',
        'auto_print': true,
        'label_width': 3.0,
        'label_height': 2.5,
      };

      final settings = PrinterSettings.fromJson(json);

      expect(settings.defaultPrinterId, equals('printer-456'));
      expect(settings.defaultPrinterName, equals('HP Printer'));
      expect(settings.autoPrint, isTrue);
      expect(settings.labelWidth, equals(3.0));
      expect(settings.labelHeight, equals(2.5));
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final settings = PrinterSettings.fromJson(json);

      expect(settings.defaultPrinterId, isNull);
      expect(settings.defaultPrinterName, isNull);
      expect(settings.autoPrint, isFalse);
      expect(settings.labelWidth, equals(1.0));
      expect(settings.labelHeight, equals(1.0));
    });

    test('toString formats correctly', () {
      const settings = PrinterSettings(
        defaultPrinterName: 'HP Printer',
        autoPrint: true,
        labelWidth: 2.0,
        labelHeight: 1.5,
      );

      final str = settings.toString();

      expect(str, contains('HP Printer'));
      expect(str, contains('autoPrint: true'));
      expect(str, contains('2.0" x 1.5"'));
    });

    test('equality works correctly', () {
      const settings1 = PrinterSettings(
        defaultPrinterId: 'printer-1',
        autoPrint: true,
      );
      const settings2 = PrinterSettings(
        defaultPrinterId: 'printer-1',
        autoPrint: true,
      );
      const settings3 = PrinterSettings(
        defaultPrinterId: 'printer-2',
        autoPrint: true,
      );

      expect(settings1, equals(settings2));
      expect(settings1, isNot(equals(settings3)));
    });
  });
}
