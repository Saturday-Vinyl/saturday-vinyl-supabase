import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/printer_settings.dart';
import '../models/production_unit.dart';
import '../repositories/settings_repository.dart';
import '../utils/app_logger.dart';

/// Service for printing thermal labels for production units
class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  final SettingsRepository _settingsRepository = SettingsRepository();
  Printer? _selectedPrinter;
  PrinterSettings? _cachedSettings;

  /// List all available printers
  Future<List<Printer>> listAvailablePrinters() async {
    try {
      AppLogger.info('Listing available printers');
      final printers = await Printing.listPrinters();
      AppLogger.info('Found ${printers.length} printers');
      return printers;
    } catch (e) {
      AppLogger.error('Error listing printers', e);
      rethrow;
    }
  }

  /// Select a printer as the default
  Future<void> selectPrinter(Printer printer) async {
    _selectedPrinter = printer;
    AppLogger.info('Selected printer: ${printer.name}');
  }

  /// Get the currently selected printer
  Printer? getSelectedPrinter() => _selectedPrinter;

  /// Load settings and configure default printer
  Future<void> loadSettings() async {
    try {
      _cachedSettings = await _settingsRepository.loadPrinterSettings();
      AppLogger.info('Loaded printer settings: $_cachedSettings');

      // If a default printer is configured, try to select it
      if (_cachedSettings?.hasDefaultPrinter() == true) {
        await _selectDefaultPrinterFromSettings();
      }
    } catch (e) {
      AppLogger.error('Error loading printer settings', e);
    }
  }

  /// Select the default printer from settings
  Future<void> _selectDefaultPrinterFromSettings() async {
    if (_cachedSettings?.defaultPrinterId == null) return;

    try {
      final printers = await listAvailablePrinters();
      final defaultPrinter = printers.firstWhere(
        (p) => p.name == _cachedSettings!.defaultPrinterId,
        orElse: () => printers.first,
      );

      await selectPrinter(defaultPrinter);
      AppLogger.info('Selected default printer from settings: ${defaultPrinter.name}');
    } catch (e) {
      AppLogger.error('Error selecting default printer from settings', e);
    }
  }

  /// Get current printer settings
  PrinterSettings? getSettings() => _cachedSettings;

  /// Find printer by ID (name)
  Future<Printer?> findPrinterById(String printerId) async {
    try {
      final printers = await listAvailablePrinters();
      return printers.firstWhere(
        (p) => p.name == printerId,
        orElse: () => throw Exception('Printer not found: $printerId'),
      );
    } catch (e) {
      AppLogger.error('Error finding printer by ID', e);
      return null;
    }
  }

  /// Generate QR label for a production unit
  ///
  /// Creates a thermal label (default 1" x 1") with:
  /// - QR code with embedded logo
  /// - Unit ID
  /// - Product name + variant
  /// - Customer name and order date (if applicable)
  ///
  /// Label size can be customized via settings or parameters
  Future<Uint8List> generateQRLabel({
    required ProductionUnit unit,
    required String productName,
    required String variantName,
    required Uint8List qrImageData,
    double? labelWidth,
    double? labelHeight,
  }) async {
    try {
      AppLogger.info('Generating QR label for unit ${unit.unitId}');

      // Use provided dimensions, or fall back to settings, or default to 1"x1"
      final width = labelWidth ?? _cachedSettings?.labelWidth ?? 1.0;
      final height = labelHeight ?? _cachedSettings?.labelHeight ?? 1.0;

      AppLogger.info('Label size: $width" x $height"');

      // Create PDF document (72 points = 1 inch)
      final pdf = pw.Document();

      // Convert QR image data to PDF image
      final qrImage = pw.MemoryImage(qrImageData);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(width * 72, height * 72, marginAll: 4),
          build: (pw.Context context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // QR Code (centered, takes most of the space)
                pw.Expanded(
                  flex: 3,
                  child: pw.Center(
                    child: pw.Image(
                      qrImage,
                      width: 50,
                      height: 50,
                    ),
                  ),
                ),

                pw.SizedBox(height: 2),

                // Unit ID (bold, larger font)
                pw.Text(
                  unit.unitId,
                  style: pw.TextStyle(
                    fontSize: 6,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),

                // Product + Variant (smaller font)
                pw.Text(
                  '$productName - $variantName',
                  style: const pw.TextStyle(fontSize: 4),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),

                // Customer name and order date (if available)
                if (unit.customerName != null)
                  pw.Text(
                    unit.customerName!,
                    style: const pw.TextStyle(fontSize: 4),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),

                if (unit.shopifyOrderNumber != null)
                  pw.Text(
                    'Order #${unit.shopifyOrderNumber}',
                    style: const pw.TextStyle(fontSize: 3),
                    textAlign: pw.TextAlign.center,
                  ),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      AppLogger.info('Generated QR label PDF (${bytes.length} bytes)');
      return bytes;
    } catch (e) {
      AppLogger.error('Error generating QR label', e);
      rethrow;
    }
  }

  /// Print QR label to the default or selected printer
  ///
  /// Sends the label to the thermal printer. Shows a print dialog if no printer
  /// is selected, or prints directly to the selected printer.
  Future<bool> printQRLabel(Uint8List labelData) async {
    try {
      if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
        AppLogger.warning('Printing not supported on this platform');
        throw UnsupportedError('Printing is only supported on desktop platforms');
      }

      AppLogger.info('Printing QR label (${labelData.length} bytes)');

      // Try direct print if printer is selected
      if (_selectedPrinter != null) {
        AppLogger.info('Printing to selected printer: ${_selectedPrinter!.name}');
        final success = await Printing.directPrintPdf(
          printer: _selectedPrinter!,
          onLayout: (PdfPageFormat format) async => labelData,
        );

        AppLogger.info('Print result: ${success ? "success" : "failed"}');
        return success;
      } else {
        // Use print dialog as fallback
        AppLogger.info('Using print dialog (no printer selected)');
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => labelData,
        );
        return true;
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error printing QR label', e, stackTrace);
      return false;
    }
  }

  /// Check if printing is available on this platform
  bool isPrintingAvailable() {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// Get printer status message
  Future<String> getPrinterStatus() async {
    if (!isPrintingAvailable()) {
      return 'Printing not available on this platform';
    }

    if (_selectedPrinter != null) {
      return 'Selected: ${_selectedPrinter!.name}';
    }

    final printers = await listAvailablePrinters();
    if (printers.isEmpty) {
      return 'No printers found';
    }

    return 'Using system default printer';
  }
}
