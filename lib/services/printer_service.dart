import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/printer_settings.dart';
import '../models/unit.dart';
import '../repositories/settings_repository.dart';
import '../utils/app_logger.dart';
import 'niimbot/niimbot_printer.dart';

/// Service for printing thermal labels for production units and RFID tags
class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  final SettingsRepository _settingsRepository = SettingsRepository();
  Printer? _selectedPrinter;
  Printer? _selectedTagPrinter;
  PrinterSettings? _cachedSettings;
  NiimbotPrinter? _niimbotPrinter;

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

  /// Load settings and configure printers
  Future<void> loadSettings() async {
    try {
      _cachedSettings = await _settingsRepository.loadPrinterSettings();
      AppLogger.info('Loaded printer settings: $_cachedSettings');

      // If a default printer is configured, try to select it
      if (_cachedSettings?.hasDefaultPrinter() == true) {
        await _selectDefaultPrinterFromSettings();
      }

      // If a tag label printer is configured, try to select it
      if (_cachedSettings?.hasTagLabelPrinter() == true) {
        await _selectTagPrinterFromSettings();
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

  /// Select the tag label printer from settings
  Future<void> _selectTagPrinterFromSettings() async {
    if (_cachedSettings?.tagLabelPrinterId == null) return;

    try {
      final printers = await listAvailablePrinters();
      final tagPrinter = printers.firstWhere(
        (p) => p.name == _cachedSettings!.tagLabelPrinterId,
        orElse: () => throw Exception('Tag printer not found'),
      );

      _selectedTagPrinter = tagPrinter;
      AppLogger.info('Selected tag label printer from settings: ${tagPrinter.name}');
    } catch (e) {
      AppLogger.error('Error selecting tag label printer from settings', e);
      // Fall back to default printer for tag labels
      _selectedTagPrinter = null;
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

  /// Generate label for a production unit
  ///
  /// Creates a thermal label (default 1" x 1") with:
  /// - QR code with embedded logo
  /// - Serial number
  /// - Product name + variant
  ///
  /// Label size can be customized via settings or parameters
  Future<Uint8List> generateUnitLabel({
    required Unit unit,
    required String productName,
    required String variantName,
    required Uint8List qrImageData,
    double? labelWidth,
    double? labelHeight,
  }) async {
    try {
      AppLogger.info('Generating unit label for ${unit.serialNumber ?? 'Unknown'}');

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
          pageFormat: PdfPageFormat(width * 72, height * 72, marginAll: 0),
          build: (pw.Context context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Small top margin to prevent cutoff
                pw.SizedBox(height: 3),

                // QR Code (centered, fixed size)
                pw.Image(
                  qrImage,
                  width: 48,
                  height: 48,
                  fit: pw.BoxFit.contain,
                  dpi: 203,
                ),

                pw.SizedBox(height: 3),

                // Product + Variant (compact)
                pw.Text(
                  '$productName - $variantName',
                  style: const pw.TextStyle(fontSize: 5),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      AppLogger.info('Generated unit label PDF (${bytes.length} bytes)');
      return bytes;
    } catch (e) {
      AppLogger.error('Error generating unit label', e);
      rethrow;
    }
  }

  /// Generate label for a production step
  ///
  /// Creates a thermal label with:
  /// - QR code
  /// - Serial number
  /// - Product name + variant
  /// - Custom label text (if provided)
  Future<Uint8List> generateStepLabel({
    required Unit unit,
    required String productName,
    required String variantName,
    required Uint8List qrImageData,
    String? labelText,
    double? labelWidth,
    double? labelHeight,
  }) async {
    try {
      AppLogger.info('Generating step label for unit ${unit.serialNumber ?? 'Unknown'}');

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
          pageFormat: PdfPageFormat(width * 72, height * 72, marginAll: 0),
          build: (pw.Context context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Small top margin to prevent cutoff
                pw.SizedBox(height: 3),

                // QR Code (centered, fixed size)
                pw.Image(
                  qrImage,
                  width: 48,
                  height: 48,
                  fit: pw.BoxFit.contain,
                  dpi: 203,
                ),

                pw.SizedBox(height: 3),

                // Product + Variant (compact)
                pw.Text(
                  '$productName - $variantName',
                  style: const pw.TextStyle(fontSize: 5),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),

                // Custom label text (if provided) - slightly larger and bold
                if (labelText != null && labelText.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    labelText,
                    style: pw.TextStyle(
                      fontSize: 6,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                ],
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      AppLogger.info('Generated step label PDF (${bytes.length} bytes)');
      return bytes;
    } catch (e) {
      AppLogger.error('Error generating step label', e);
      rethrow;
    }
  }

  /// Generate label for an RFID tag
  ///
  /// Creates a minimal thermal label with just the QR code centered.
  /// The QR code contains the tag URL which encodes all tag information.
  ///
  /// Label size can be customized via settings or parameters.
  Future<Uint8List> generateTagLabel({
    required Uint8List qrImageData,
    double? labelWidth,
    double? labelHeight,
  }) async {
    try {
      AppLogger.info('Generating tag label');

      // Use provided dimensions, or fall back to tag label settings, or default to 1"x1"
      final width = labelWidth ?? _cachedSettings?.tagLabelWidth ?? 1.0;
      final height = labelHeight ?? _cachedSettings?.tagLabelHeight ?? 1.0;

      AppLogger.info('Tag label size: $width" x $height"');

      // Create PDF document (72 points = 1 inch)
      final pdf = pw.Document();

      // Convert QR image data to PDF image
      final qrImage = pw.MemoryImage(qrImageData);

      // Calculate QR code size to fill the label appropriately
      // Leave small margins (4 points = ~0.055") on each side
      final labelWidthPts = width * 72;
      final labelHeightPts = height * 72;
      const margin = 4.0;
      final availableSize = (labelWidthPts < labelHeightPts ? labelWidthPts : labelHeightPts) - (margin * 2);
      final qrSize = availableSize > 0 ? availableSize : 48.0;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(labelWidthPts, labelHeightPts, marginAll: 0),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(
                qrImage,
                width: qrSize,
                height: qrSize,
                fit: pw.BoxFit.contain,
                dpi: 203,
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      AppLogger.info('Generated tag label PDF (${bytes.length} bytes)');
      return bytes;
    } catch (e) {
      AppLogger.error('Error generating tag label', e);
      rethrow;
    }
  }

  /// Print label to the default or selected printer
  ///
  /// Sends the label to the thermal printer. Shows a print dialog if no printer
  /// is selected, or prints directly to the selected printer.
  ///
  /// Set [useTagPrinter] to true to use the tag label printer instead of the
  /// default printer. Falls back to default printer if no tag printer is configured.
  ///
  /// For tag labels, if the tag printer type is set to Niimbot, the label will
  /// be printed via the Niimbot printer using USB serial.
  Future<bool> printLabel(
    Uint8List labelData, {
    double? labelWidth,
    double? labelHeight,
    bool useTagPrinter = false,
  }) async {
    try {
      if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
        AppLogger.warning('Printing not supported on this platform');
        throw UnsupportedError('Printing is only supported on desktop platforms');
      }

      // Check if we should use Niimbot printer for tag labels
      if (useTagPrinter && _cachedSettings?.tagPrinterType == TagPrinterType.niimbot) {
        return await _printToNiimbot(labelData);
      }

      // Determine which printer to use
      final printer = useTagPrinter
          ? (_selectedTagPrinter ?? _selectedPrinter)
          : _selectedPrinter;

      // Get label dimensions based on printer type
      final double width;
      final double height;
      if (useTagPrinter) {
        width = labelWidth ?? _cachedSettings?.tagLabelWidth ?? 1.0;
        height = labelHeight ?? _cachedSettings?.tagLabelHeight ?? 1.0;
      } else {
        width = labelWidth ?? _cachedSettings?.labelWidth ?? 1.0;
        height = labelHeight ?? _cachedSettings?.labelHeight ?? 1.0;
      }

      AppLogger.info('Printing label (${labelData.length} bytes) at $width" x $height"');

      // Create the exact page format for the label (72 points = 1 inch)
      final pageFormat = PdfPageFormat(
        width * PdfPageFormat.inch,
        height * PdfPageFormat.inch,
        marginAll: 0, // No margins for label printing
      );

      AppLogger.info('Using page format: ${pageFormat.width}pt x ${pageFormat.height}pt');

      // Try direct print if printer is selected
      if (printer != null) {
        AppLogger.info('Printing to ${useTagPrinter ? "tag" : "default"} printer: ${printer.name}');
        final success = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (PdfPageFormat format) async {
            AppLogger.info('Printer requested format: ${format.width}pt x ${format.height}pt');
            return labelData;
          },
          format: pageFormat, // Specify the exact page format
        );

        AppLogger.info('Print result: ${success ? "success" : "failed"}');
        return success;
      } else {
        // Use print dialog as fallback
        AppLogger.info('Using print dialog (no printer selected)');
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => labelData,
          format: pageFormat,
        );
        return true;
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error printing label', e, stackTrace);
      return false;
    }
  }

  /// Print an image to the Niimbot printer
  ///
  /// Converts the QR code image data to the format expected by the Niimbot
  /// printer and sends it via USB serial.
  Future<bool> _printToNiimbot(Uint8List imageData) async {
    try {
      final port = _cachedSettings?.niimbotPort;
      if (port == null) {
        AppLogger.error('Niimbot port not configured');
        return false;
      }

      final density = _cachedSettings?.niimbotDensity ?? 3;

      AppLogger.info('Printing to Niimbot printer on $port (density: $density)');

      // Create or reuse Niimbot printer instance
      _niimbotPrinter ??= NiimbotPrinter();

      // Connect if not already connected
      if (!_niimbotPrinter!.isConnected) {
        final connected = await _niimbotPrinter!.connect(port);
        if (!connected) {
          AppLogger.error('Failed to connect to Niimbot printer');
          return false;
        }
      }

      // Print the image
      final success = await _niimbotPrinter!.printImage(imageData, density: density);

      AppLogger.info('Niimbot print result: ${success ? "success" : "failed"}');
      return success;
    } catch (e, stackTrace) {
      AppLogger.error('Error printing to Niimbot', e, stackTrace);
      return false;
    }
  }

  /// Print a tag label directly to the Niimbot printer
  ///
  /// This method takes raw PNG image data (like a QR code) and prints it
  /// directly to the Niimbot printer without going through PDF generation.
  Future<bool> printTagLabelToNiimbot(Uint8List qrImageData) async {
    try {
      final port = _cachedSettings?.niimbotPort;
      if (port == null) {
        AppLogger.error('Niimbot port not configured');
        return false;
      }

      final density = _cachedSettings?.niimbotDensity ?? 3;

      AppLogger.info('Printing tag label to Niimbot printer on $port');

      // Create or reuse Niimbot printer instance
      _niimbotPrinter ??= NiimbotPrinter();

      // Connect if not already connected
      if (!_niimbotPrinter!.isConnected) {
        final connected = await _niimbotPrinter!.connect(port);
        if (!connected) {
          AppLogger.error('Failed to connect to Niimbot printer');
          return false;
        }
      }

      // The qrImageData is already a PNG - send it directly
      final success = await _niimbotPrinter!.printImage(qrImageData, density: density);

      AppLogger.info('Niimbot tag label print result: ${success ? "success" : "failed"}');
      return success;
    } catch (e, stackTrace) {
      AppLogger.error('Error printing tag label to Niimbot', e, stackTrace);
      return false;
    }
  }

  /// Disconnect from the Niimbot printer
  void disconnectNiimbot() {
    _niimbotPrinter?.disconnect();
    _niimbotPrinter = null;
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

  /// Preview PDF for debugging - opens system print/preview dialog
  Future<void> previewPdf(Uint8List pdfData, String filename) async {
    try {
      AppLogger.info('Opening PDF preview for debugging (${pdfData.length} bytes)');

      await Printing.sharePdf(
        bytes: pdfData,
        filename: filename,
      );

      AppLogger.info('PDF preview opened successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Error opening PDF preview', e, stackTrace);
    }
  }
}
