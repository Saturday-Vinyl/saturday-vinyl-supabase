import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../../config/theme.dart';
import '../../models/printer_settings.dart';
import '../../models/production_unit.dart';
import '../../models/app_association.dart';
import '../../providers/settings_provider.dart';
import '../../services/printer_service.dart';
import '../../services/qr_service.dart';
import '../../repositories/settings_repository.dart';
import '../../utils/app_logger.dart';
import '../../widgets/settings/scanner_config_card.dart';
import '../../widgets/settings/gcode_sync_card.dart';
import '../../widgets/settings/machine_config_card.dart';
import '../settings/machine_macros_settings_screen.dart';

/// Settings screen for application configuration
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final PrinterService _printerService = PrinterService();
  final QRService _qrService = QRService();
  final SettingsRepository _settingsRepository = SettingsRepository();

  List<Printer> _availablePrinters = [];
  bool _isLoadingPrinters = false;
  bool _isSaving = false;
  bool _isTesting = false;

  // Form state
  String? _selectedPrinterId;
  String? _selectedPrinterName;
  bool _autoPrint = false;
  double _labelWidth = 1.0;
  double _labelHeight = 1.0;

  // File associations state
  Map<String, AppAssociation> _appAssociations = {};
  bool _isLoadingAssociations = false;

  // Common file types for production
  static const List<String> _commonFileTypes = [
    '.gcode',
    '.nc',
    '.svg',
    '.ai',
    '.dxf',
    '.pdf',
  ];

  @override
  void initState() {
    super.initState();
    _loadPrinters();
    _loadSettings();
    _loadAppAssociations();
  }

  Future<void> _loadPrinters() async {
    if (!_printerService.isPrintingAvailable()) {
      AppLogger.warning('Printing not available on this platform');
      return;
    }

    setState(() => _isLoadingPrinters = true);

    try {
      AppLogger.info('Loading available printers...');
      final printers = await _printerService.listAvailablePrinters();
      AppLogger.info('Found ${printers.length} printers: ${printers.map((p) => p.name).join(", ")}');

      setState(() {
        _availablePrinters = printers;
        _isLoadingPrinters = false;
      });

      if (printers.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No printers found. Please check your system printer settings.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error loading printers', e, stackTrace);
      setState(() => _isLoadingPrinters = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading printers: $e\n\nPlease check app permissions.'),
            duration: Duration(seconds: 7),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _loadSettings() {
    final settingsAsync = ref.read(printerSettingsProvider);
    settingsAsync.whenData((settings) {
      setState(() {
        _selectedPrinterId = settings.defaultPrinterId;
        _selectedPrinterName = settings.defaultPrinterName;
        _autoPrint = settings.autoPrint;
        _labelWidth = settings.labelWidth;
        _labelHeight = settings.labelHeight;
      });
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final newSettings = PrinterSettings(
        defaultPrinterId: _selectedPrinterId,
        defaultPrinterName: _selectedPrinterName,
        autoPrint: _autoPrint,
        labelWidth: _labelWidth,
        labelHeight: _labelHeight,
      );

      if (!newSettings.isValid()) {
        throw Exception('Invalid label size. Must be between 0.5" and 4.0"');
      }

      await ref
          .read(printerSettingsProvider.notifier)
          .updateSettings(newSettings);

      // Reload printer service settings
      await _printerService.loadSettings();

      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error saving settings', e);
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _testPrint() async {
    if (_selectedPrinterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a printer first')),
      );
      return;
    }

    setState(() => _isTesting = true);

    try {
      AppLogger.info('Starting test print...');

      // Generate a test QR code with timeout
      AppLogger.info('Generating QR code...');
      final qrCode = await _qrService.generateQRCode(
        'TEST-LABEL-${DateTime.now().millisecondsSinceEpoch}',
        size: 512,  // Higher resolution for better thermal printing
        embedLogo: true,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('QR code generation timed out');
        },
      );
      AppLogger.info('QR code generated successfully');

      // Create test unit data
      AppLogger.info('Generating test label PDF...');
      final testLabel = await _printerService.generateQRLabel(
        unit: _createTestUnit(),
        productName: 'Test Product',
        variantName: 'Test Variant',
        qrImageData: qrCode,
        labelWidth: _labelWidth,
        labelHeight: _labelHeight,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Label generation timed out');
        },
      );
      AppLogger.info('Test label PDF generated (${testLabel.length} bytes)');

      // Preview PDF for debugging - this will open a share dialog
      AppLogger.info('Opening PDF preview for inspection...');
      await _printerService.previewPdf(
        testLabel,
        'test-label-${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      // Find and select the printer
      AppLogger.info('Finding printer: $_selectedPrinterId');
      final printer = await _printerService.findPrinterById(_selectedPrinterId!);
      if (printer != null) {
        AppLogger.info('Selecting printer: ${printer.name}');
        await _printerService.selectPrinter(printer);
      } else {
        throw Exception('Printer not found: $_selectedPrinterId');
      }

      // Print the test label with timeout, passing label dimensions
      AppLogger.info('Sending to printer with dimensions: $_labelWidth" x $_labelHeight"...');
      final success = await _printerService.printQRLabel(
        testLabel,
        labelWidth: _labelWidth,
        labelHeight: _labelHeight,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          AppLogger.warning('Print operation timed out after 30 seconds');
          return false;
        },
      );
      AppLogger.info('Print operation completed: $success');

      setState(() => _isTesting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                success ? 'Test label sent to printer!' : 'Print failed - check printer connection'),
            backgroundColor:
                success ? SaturdayColors.success : SaturdayColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } on TimeoutException catch (e) {
      AppLogger.error('Test print timeout', e);
      setState(() => _isTesting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print timeout: ${e.message}\n\nThe printer may be offline or busy.'),
            backgroundColor: SaturdayColors.error,
            duration: const Duration(seconds: 7),
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error testing print', e, stackTrace);
      setState(() => _isTesting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error testing print: $e'),
            backgroundColor: SaturdayColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Create a test production unit for test printing
  ProductionUnit _createTestUnit() {
    final now = DateTime.now();
    return ProductionUnit(
      id: 'test-id',
      uuid: 'test-uuid',
      unitId: 'SV-TEST-00001',
      productId: 'test-product',
      variantId: 'test-variant',
      qrCodeUrl: 'https://example.com/test-qr.png',
      customerName: 'Test Customer',
      shopifyOrderNumber: 'TEST-123',
      isCompleted: false,
      createdAt: now,
      createdBy: 'test',
    );
  }

  // Load app associations from storage
  Future<void> _loadAppAssociations() async {
    setState(() => _isLoadingAssociations = true);

    try {
      AppLogger.info('Loading app associations...');
      final associations = await _settingsRepository.getAllAppAssociations();

      setState(() {
        _appAssociations = associations;
        _isLoadingAssociations = false;
      });

      AppLogger.info('Loaded ${associations.length} app associations');
    } catch (e, stackTrace) {
      AppLogger.error('Error loading app associations', e, stackTrace);
      setState(() => _isLoadingAssociations = false);
    }
  }

  // Pick an application executable for a file type
  Future<void> _pickApplicationForFileType(String fileType) async {
    try {
      AppLogger.info('Picking application for file type: $fileType');

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select application for $fileType files',
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) {
        AppLogger.info('No application selected');
        return;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        AppLogger.warning('Selected file has no path');
        return;
      }

      // Get app name from path
      final appName = path.basenameWithoutExtension(filePath);

      AppLogger.info('Selected app: $appName at $filePath');

      // Save the association
      await _settingsRepository.setAppAssociation(fileType, filePath, appName);

      // Reload associations
      await _loadAppAssociations();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileType files will now open in $appName'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error picking application', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting application: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  // Remove app association for a file type (use system default)
  Future<void> _removeAppAssociation(String fileType) async {
    try {
      AppLogger.info('Removing app association for: $fileType');

      await _settingsRepository.removeAppAssociation(fileType);
      await _loadAppAssociations();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileType files will use system default'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error removing app association', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing association: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(printerSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading settings: $error'),
        ),
        data: (settings) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Printer Configuration Section (desktop only)
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                _buildPrinterConfigurationSection(),

              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const SizedBox(height: 32),

              // File Associations Section (desktop only)
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                _buildFileAssociationsSection(),

              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const SizedBox(height: 32),

              // Scanner Configuration Section (desktop only)
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const ScannerConfigCard(),

              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const SizedBox(height: 32),

              // gCode Repository Sync Section (desktop only)
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const GCodeSyncCard(),

              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const SizedBox(height: 32),

              // Machine Configuration Section (desktop only)
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const MachineConfigCard(),

              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const SizedBox(height: 32),

              // Machine Macros Section (desktop only)
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                _buildMachineMacrosSection(),

              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                const SizedBox(height: 32),

              // Save button
              if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.primaryDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Save Settings'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrinterConfigurationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Printer Configuration',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(height: 24),

            // Default Printer Dropdown
            const Text(
              'Default Printer',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _isLoadingPrinters
                ? const CircularProgressIndicator()
                : DropdownButtonFormField<String>(
                    value: _selectedPrinterId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      hintText: 'Select a printer',
                    ),
                    items: _availablePrinters.map((printer) {
                      return DropdownMenuItem(
                        value: printer.name,
                        child: Text(printer.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPrinterId = value;
                        _selectedPrinterName = value;
                      });
                    },
                  ),

            const SizedBox(height: 20),

            // Auto-print checkbox
            CheckboxListTile(
              title: const Text('Auto-print labels after unit creation'),
              subtitle: const Text(
                'Labels will print automatically without showing preview',
              ),
              value: _autoPrint,
              onChanged: (value) {
                setState(() => _autoPrint = value ?? false);
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 20),

            // Label Size Configuration
            const Text(
              'Label Size',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Width (inches)'),
                      const SizedBox(height: 4),
                      TextFormField(
                        initialValue: _labelWidth.toStringAsFixed(1),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) {
                          final width = double.tryParse(value);
                          if (width != null) {
                            setState(() => _labelWidth = width);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Height (inches)'),
                      const SizedBox(height: 4),
                      TextFormField(
                        initialValue: _labelHeight.toStringAsFixed(1),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) {
                          final height = double.tryParse(value);
                          if (height != null) {
                            setState(() => _labelHeight = height);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Recommended: 1.0" x 1.0" (default)',
              style: TextStyle(
                fontSize: 12,
                color: SaturdayColors.secondaryGrey,
              ),
            ),

            const SizedBox(height: 24),

            // Test Print Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _testPrint,
                icon: _isTesting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print),
                label: Text(_isTesting ? 'Printing...' : 'Test Print'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileAssociationsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'File Associations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure which applications open production files',
              style: TextStyle(
                fontSize: 14,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
            const SizedBox(height: 16),

            // File type associations
            if (_isLoadingAssociations)
              const Center(child: CircularProgressIndicator())
            else
              ..._commonFileTypes.map((fileType) {
                final association = _appAssociations[fileType];
                final appName = association?.appName ?? 'System Default';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      // File type
                      SizedBox(
                        width: 80,
                        child: Text(
                          fileType,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Associated app
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: SaturdayColors.secondaryGrey.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            appName,
                            style: TextStyle(
                              color: association == null
                                  ? SaturdayColors.secondaryGrey
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Change button
                      OutlinedButton(
                        onPressed: () => _pickApplicationForFileType(fileType),
                        child: const Text('Change'),
                      ),

                      // Remove button (only show if association exists)
                      if (association != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _removeAppAssociation(fileType),
                          tooltip: 'Use system default',
                          color: SaturdayColors.error,
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineMacrosSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Machine Macros',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Divider(height: 24),
            const Text(
              'Create and manage gcode macros for quick execution on CNC and Laser machines.',
              style: TextStyle(
                fontSize: 14,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MachineMacrosSettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('Manage Macros'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaturdayColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
