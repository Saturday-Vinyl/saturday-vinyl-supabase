import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../config/theme.dart';
import '../../models/unit.dart';
import '../../services/printer_service.dart';
import '../../utils/app_logger.dart';
import 'label_layout.dart';

/// Dialog for previewing and printing a thermal label
///
/// Shows a preview of the 1" x 1" label and allows the user to:
/// - See how the label will look
/// - Select a printer
/// - Print the label
class PrintPreviewDialog extends ConsumerStatefulWidget {
  final Unit unit;
  final String productName;
  final String variantName;
  final Uint8List qrImageData;

  const PrintPreviewDialog({
    super.key,
    required this.unit,
    required this.productName,
    required this.variantName,
    required this.qrImageData,
  });

  @override
  ConsumerState<PrintPreviewDialog> createState() => _PrintPreviewDialogState();
}

class _PrintPreviewDialogState extends ConsumerState<PrintPreviewDialog> {
  final PrinterService _printerService = PrinterService();

  List<Printer> _printers = [];
  Printer? _selectedPrinter;
  bool _isLoading = false;
  bool _isPrinting = false;
  String? _errorMessage;
  Uint8List? _labelData;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
    _generateLabel();
  }

  Future<void> _loadPrinters() async {
    if (!_printerService.isPrintingAvailable()) {
      setState(() {
        _errorMessage = 'Printing is not available on this platform';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final printers = await _printerService.listAvailablePrinters();
      setState(() {
        _printers = printers;
        _selectedPrinter = _printerService.getSelectedPrinter() ??
                          (printers.isNotEmpty ? printers.first : null);
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Error loading printers', e);
      setState(() {
        _errorMessage = 'Failed to load printers: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _generateLabel() async {
    try {
      final labelData = await _printerService.generateUnitLabel(
        unit: widget.unit,
        productName: widget.productName,
        variantName: widget.variantName,
        qrImageData: widget.qrImageData,
      );

      setState(() => _labelData = labelData);
    } catch (e) {
      AppLogger.error('Error generating label', e);
      setState(() {
        _errorMessage = 'Failed to generate label: $e';
      });
    }
  }

  Future<void> _printLabel() async {
    if (_labelData == null) {
      setState(() => _errorMessage = 'Label not ready for printing');
      return;
    }

    setState(() {
      _isPrinting = true;
      _errorMessage = null;
    });

    try {
      if (_selectedPrinter != null) {
        await _printerService.selectPrinter(_selectedPrinter!);
      }

      final success = await _printerService.printLabel(
        _labelData!,
        labelWidth: 1.0,  // 1 inch labels
        labelHeight: 1.0,
      );

      if (success) {
        if (mounted) {
          Navigator.of(context).pop(true); // Return true to indicate success
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Label printed successfully'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Printing failed. Please check printer connection.';
          _isPrinting = false;
        });
      }
    } catch (e) {
      AppLogger.error('Error printing label', e);
      setState(() {
        _errorMessage = 'Failed to print: $e';
        _isPrinting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Print Label'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Label preview
            const Text(
              'Label Preview (1" x 1")',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Show label at 3x scale for visibility
            Center(
              child: LabelLayout(
                unit: widget.unit,
                productName: widget.productName,
                variantName: widget.variantName,
                qrCodeUrl: widget.unit.qrCodeUrl ?? '',
                scale: 3.0,
              ),
            ),

            const SizedBox(height: 24),

            // Printer selection
            if (_printerService.isPrintingAvailable() && _printers.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Printer',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Printer>(
                    initialValue: _selectedPrinter,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _printers.map((printer) {
                      return DropdownMenuItem(
                        value: printer,
                        child: Text(printer.name),
                      );
                    }).toList(),
                    onChanged: (printer) {
                      setState(() => _selectedPrinter = printer);
                    },
                  ),
                ],
              ),

            // Error message
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SaturdayColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SaturdayColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: SaturdayColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: SaturdayColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Loading indicator
            if (_isLoading || _isPrinting)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        // Cancel button
        TextButton(
          onPressed: _isPrinting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),

        // Print button
        ElevatedButton.icon(
          onPressed: (_isPrinting || _labelData == null || !_printerService.isPrintingAvailable())
              ? null
              : _printLabel,
          icon: const Icon(Icons.print),
          label: Text(_isPrinting ? 'Printing...' : 'Print'),
          style: ElevatedButton.styleFrom(
            backgroundColor: SaturdayColors.primaryDark,
            foregroundColor: SaturdayColors.white,
          ),
        ),
      ],
    );
  }
}
