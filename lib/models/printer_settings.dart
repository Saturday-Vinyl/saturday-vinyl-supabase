import 'package:equatable/equatable.dart';

/// Enum for tag label printer type
enum TagPrinterType {
  /// Standard system printer (via CUPS/printing package)
  standard,
  /// Niimbot printer (via USB serial)
  niimbot,
}

/// Settings for thermal label printing
///
/// Stores user preferences for printer configuration including:
/// - Default printer selection (for production labels)
/// - Tag label printer selection (separate printer for RFID tag labels)
/// - Niimbot printer configuration (USB serial)
/// - Auto-print behavior
/// - Label size configuration (per label type)
class PrinterSettings extends Equatable {
  /// The ID of the default printer (null if not set)
  final String? defaultPrinterId;

  /// The name of the default printer (for display purposes)
  final String? defaultPrinterName;

  /// The ID of the tag label printer (null to use default printer)
  final String? tagLabelPrinterId;

  /// The name of the tag label printer (for display purposes)
  final String? tagLabelPrinterName;

  /// Whether to automatically print labels after unit creation (skip preview)
  final bool autoPrint;

  /// Label width in inches for production labels (default: 1.0)
  final double labelWidth;

  /// Label height in inches for production labels (default: 1.0)
  final double labelHeight;

  /// Tag label width in inches (default: 1.0)
  final double tagLabelWidth;

  /// Tag label height in inches (default: 1.0)
  final double tagLabelHeight;

  /// Type of printer to use for tag labels
  final TagPrinterType tagPrinterType;

  /// Serial port path for Niimbot printer (e.g., /dev/cu.usbmodem2101)
  final String? niimbotPort;

  /// Print density for Niimbot printer (1-5, default 3)
  final int niimbotDensity;

  const PrinterSettings({
    this.defaultPrinterId,
    this.defaultPrinterName,
    this.tagLabelPrinterId,
    this.tagLabelPrinterName,
    this.autoPrint = false,
    this.labelWidth = 1.0,
    this.labelHeight = 1.0,
    this.tagLabelWidth = 1.0,
    this.tagLabelHeight = 1.0,
    this.tagPrinterType = TagPrinterType.standard,
    this.niimbotPort,
    this.niimbotDensity = 3,
  });

  /// Default settings (no printer selected, auto-print disabled, 1"x1" labels)
  const PrinterSettings.defaultSettings()
      : defaultPrinterId = null,
        defaultPrinterName = null,
        tagLabelPrinterId = null,
        tagLabelPrinterName = null,
        autoPrint = false,
        labelWidth = 1.0,
        labelHeight = 1.0,
        tagLabelWidth = 1.0,
        tagLabelHeight = 1.0,
        tagPrinterType = TagPrinterType.standard,
        niimbotPort = null,
        niimbotDensity = 3;

  /// Check if settings are valid
  bool isValid() {
    // Label size must be positive and reasonable (between 0.5" and 4")
    if (labelWidth < 0.5 || labelWidth > 4.0) return false;
    if (labelHeight < 0.5 || labelHeight > 4.0) return false;
    if (tagLabelWidth < 0.5 || tagLabelWidth > 4.0) return false;
    if (tagLabelHeight < 0.5 || tagLabelHeight > 4.0) return false;
    // Niimbot density must be 1-5
    if (niimbotDensity < 1 || niimbotDensity > 5) return false;
    return true;
  }

  /// Check if a default printer is configured
  bool hasDefaultPrinter() => defaultPrinterId != null;

  /// Check if a tag label printer is configured
  bool hasTagLabelPrinter() {
    if (tagPrinterType == TagPrinterType.niimbot) {
      return niimbotPort != null;
    }
    return tagLabelPrinterId != null;
  }

  /// Check if Niimbot printer is configured
  bool hasNiimbotPrinter() => niimbotPort != null;

  /// Get formatted label size string (e.g., "1.0\" x 1.0\"")
  String getFormattedLabelSize() {
    return '${labelWidth.toStringAsFixed(1)}" x ${labelHeight.toStringAsFixed(1)}"';
  }

  /// Create a copy with updated fields
  PrinterSettings copyWith({
    String? defaultPrinterId,
    String? defaultPrinterName,
    String? tagLabelPrinterId,
    String? tagLabelPrinterName,
    bool? autoPrint,
    double? labelWidth,
    double? labelHeight,
    double? tagLabelWidth,
    double? tagLabelHeight,
    TagPrinterType? tagPrinterType,
    String? niimbotPort,
    int? niimbotDensity,
    bool clearTagLabelPrinter = false,
    bool clearNiimbotPort = false,
  }) {
    return PrinterSettings(
      defaultPrinterId: defaultPrinterId ?? this.defaultPrinterId,
      defaultPrinterName: defaultPrinterName ?? this.defaultPrinterName,
      tagLabelPrinterId: clearTagLabelPrinter ? null : (tagLabelPrinterId ?? this.tagLabelPrinterId),
      tagLabelPrinterName: clearTagLabelPrinter ? null : (tagLabelPrinterName ?? this.tagLabelPrinterName),
      autoPrint: autoPrint ?? this.autoPrint,
      labelWidth: labelWidth ?? this.labelWidth,
      labelHeight: labelHeight ?? this.labelHeight,
      tagLabelWidth: tagLabelWidth ?? this.tagLabelWidth,
      tagLabelHeight: tagLabelHeight ?? this.tagLabelHeight,
      tagPrinterType: tagPrinterType ?? this.tagPrinterType,
      niimbotPort: clearNiimbotPort ? null : (niimbotPort ?? this.niimbotPort),
      niimbotDensity: niimbotDensity ?? this.niimbotDensity,
    );
  }

  /// Create from JSON
  factory PrinterSettings.fromJson(Map<String, dynamic> json) {
    return PrinterSettings(
      defaultPrinterId: json['default_printer_id'] as String?,
      defaultPrinterName: json['default_printer_name'] as String?,
      tagLabelPrinterId: json['tag_label_printer_id'] as String?,
      tagLabelPrinterName: json['tag_label_printer_name'] as String?,
      autoPrint: json['auto_print'] as bool? ?? false,
      labelWidth: (json['label_width'] as num?)?.toDouble() ?? 1.0,
      labelHeight: (json['label_height'] as num?)?.toDouble() ?? 1.0,
      tagLabelWidth: (json['tag_label_width'] as num?)?.toDouble() ?? 1.0,
      tagLabelHeight: (json['tag_label_height'] as num?)?.toDouble() ?? 1.0,
      tagPrinterType: _tagPrinterTypeFromString(json['tag_printer_type'] as String?),
      niimbotPort: json['niimbot_port'] as String?,
      niimbotDensity: (json['niimbot_density'] as int?) ?? 3,
    );
  }

  static TagPrinterType _tagPrinterTypeFromString(String? value) {
    switch (value) {
      case 'niimbot':
        return TagPrinterType.niimbot;
      default:
        return TagPrinterType.standard;
    }
  }

  static String _tagPrinterTypeToString(TagPrinterType type) {
    switch (type) {
      case TagPrinterType.niimbot:
        return 'niimbot';
      case TagPrinterType.standard:
        return 'standard';
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'default_printer_id': defaultPrinterId,
      'default_printer_name': defaultPrinterName,
      'tag_label_printer_id': tagLabelPrinterId,
      'tag_label_printer_name': tagLabelPrinterName,
      'auto_print': autoPrint,
      'label_width': labelWidth,
      'label_height': labelHeight,
      'tag_label_width': tagLabelWidth,
      'tag_label_height': tagLabelHeight,
      'tag_printer_type': _tagPrinterTypeToString(tagPrinterType),
      'niimbot_port': niimbotPort,
      'niimbot_density': niimbotDensity,
    };
  }

  @override
  List<Object?> get props => [
        defaultPrinterId,
        defaultPrinterName,
        tagLabelPrinterId,
        tagLabelPrinterName,
        autoPrint,
        labelWidth,
        labelHeight,
        tagLabelWidth,
        tagLabelHeight,
        tagPrinterType,
        niimbotPort,
        niimbotDensity,
      ];

  @override
  String toString() {
    return 'PrinterSettings(printer: $defaultPrinterName, autoPrint: $autoPrint, size: ${getFormattedLabelSize()})';
  }
}
