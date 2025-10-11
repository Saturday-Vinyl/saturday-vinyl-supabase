import 'package:equatable/equatable.dart';

/// Settings for thermal label printing
///
/// Stores user preferences for printer configuration including:
/// - Default printer selection
/// - Auto-print behavior
/// - Label size configuration
class PrinterSettings extends Equatable {
  /// The ID of the default printer (null if not set)
  final String? defaultPrinterId;

  /// The name of the default printer (for display purposes)
  final String? defaultPrinterName;

  /// Whether to automatically print labels after unit creation (skip preview)
  final bool autoPrint;

  /// Label width in inches (default: 1.0)
  final double labelWidth;

  /// Label height in inches (default: 1.0)
  final double labelHeight;

  const PrinterSettings({
    this.defaultPrinterId,
    this.defaultPrinterName,
    this.autoPrint = false,
    this.labelWidth = 1.0,
    this.labelHeight = 1.0,
  });

  /// Default settings (no printer selected, auto-print disabled, 1"x1" labels)
  const PrinterSettings.defaultSettings()
      : defaultPrinterId = null,
        defaultPrinterName = null,
        autoPrint = false,
        labelWidth = 1.0,
        labelHeight = 1.0;

  /// Check if settings are valid
  bool isValid() {
    // Label size must be positive and reasonable (between 0.5" and 4")
    if (labelWidth < 0.5 || labelWidth > 4.0) return false;
    if (labelHeight < 0.5 || labelHeight > 4.0) return false;
    return true;
  }

  /// Check if a default printer is configured
  bool hasDefaultPrinter() => defaultPrinterId != null;

  /// Get formatted label size string (e.g., "1.0\" x 1.0\"")
  String getFormattedLabelSize() {
    return '${labelWidth.toStringAsFixed(1)}" x ${labelHeight.toStringAsFixed(1)}"';
  }

  /// Create a copy with updated fields
  PrinterSettings copyWith({
    String? defaultPrinterId,
    String? defaultPrinterName,
    bool? autoPrint,
    double? labelWidth,
    double? labelHeight,
  }) {
    return PrinterSettings(
      defaultPrinterId: defaultPrinterId ?? this.defaultPrinterId,
      defaultPrinterName: defaultPrinterName ?? this.defaultPrinterName,
      autoPrint: autoPrint ?? this.autoPrint,
      labelWidth: labelWidth ?? this.labelWidth,
      labelHeight: labelHeight ?? this.labelHeight,
    );
  }

  /// Create from JSON
  factory PrinterSettings.fromJson(Map<String, dynamic> json) {
    return PrinterSettings(
      defaultPrinterId: json['default_printer_id'] as String?,
      defaultPrinterName: json['default_printer_name'] as String?,
      autoPrint: json['auto_print'] as bool? ?? false,
      labelWidth: (json['label_width'] as num?)?.toDouble() ?? 1.0,
      labelHeight: (json['label_height'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'default_printer_id': defaultPrinterId,
      'default_printer_name': defaultPrinterName,
      'auto_print': autoPrint,
      'label_width': labelWidth,
      'label_height': labelHeight,
    };
  }

  @override
  List<Object?> get props => [
        defaultPrinterId,
        defaultPrinterName,
        autoPrint,
        labelWidth,
        labelHeight,
      ];

  @override
  String toString() {
    return 'PrinterSettings(printer: $defaultPrinterName, autoPrint: $autoPrint, size: ${getFormattedLabelSize()})';
  }
}
