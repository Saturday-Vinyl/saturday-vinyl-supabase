import 'package:saturday_app/utils/app_logger.dart';

/// A single entry parsed from an EagleCAD BOM export
class ParsedBomEntry {
  final String referenceDesignator;
  final String value;
  final String package;
  final int quantity;
  final Map<String, String> supplierParts; // e.g. {'LCSC': 'C12345', 'DIGIKEY': 'ABC-ND'}
  final String? description;
  final String? manufacturerPartNumber;
  final String? manufacturer;

  const ParsedBomEntry({
    required this.referenceDesignator,
    required this.value,
    required this.package,
    required this.quantity,
    this.supplierParts = const {},
    this.description,
    this.manufacturerPartNumber,
    this.manufacturer,
  });

  /// Generate a readable part name from value, description, and package
  String get suggestedPartName {
    if (description != null && description!.isNotEmpty) {
      return description!;
    }
    if (value.isNotEmpty && package.isNotEmpty) {
      return '$value ($package)';
    }
    return value.isNotEmpty ? value : package;
  }

  /// Generate a suggested part number — prefer manufacturer PN when available
  String get suggestedPartNumber {
    if (manufacturerPartNumber != null && manufacturerPartNumber!.isNotEmpty) {
      return manufacturerPartNumber!;
    }
    final prefix = referenceDesignator.replaceAll(RegExp(r'\d+'), '');
    return '${prefix}_${value}_$package'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')
        .toLowerCase();
  }
}

/// Parser for EagleCAD BOM export files (CSV format).
///
/// Supports the standard EagleCAD CSV export format with columns:
/// Qty, Value, Device, Package, Parts, plus custom attributes like
/// LCSC_PART, DIGIKEY_PART, MOUSER_PART.
class EaglecadBomParser {
  /// Parse a CSV BOM string into a list of entries.
  ///
  /// Handles multiple CSV formats:
  /// - Standard EagleCAD: "Qty";"Value";"Device";"Package";"Parts"
  /// - KiCad-style: "Reference","Value","Footprint","Quantity"
  /// - Generic: auto-detects columns by header names
  List<ParsedBomEntry> parseCsv(String csvContent) {
    final lines = csvContent.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return [];

    // Detect delimiter
    final delimiter = _detectDelimiter(lines.first);

    // Parse header
    final headers = _parseCsvLine(lines.first, delimiter)
        .map((h) => h.trim().toLowerCase())
        .toList();

    if (headers.isEmpty) return [];

    // Map column indices
    final colMap = _mapColumns(headers);

    if (colMap['value'] == null && colMap['parts'] == null) {
      AppLogger.warning('BOM CSV: could not identify required columns');
      return [];
    }

    // Parse data rows
    final entries = <ParsedBomEntry>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final fields = _parseCsvLine(line, delimiter);
      if (fields.isEmpty) continue;

      try {
        final entry = _parseRow(fields, colMap, headers);
        if (entry != null) entries.add(entry);
      } catch (e) {
        AppLogger.warning('BOM CSV: skipping row ${i + 1}: $e');
      }
    }

    AppLogger.info('BOM CSV: parsed ${entries.length} entries');
    return entries;
  }

  String _detectDelimiter(String headerLine) {
    if (headerLine.contains(';')) return ';';
    if (headerLine.contains('\t')) return '\t';
    return ',';
  }

  List<String> _parseCsvLine(String line, String delimiter) {
    final fields = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == delimiter && !inQuotes) {
        fields.add(current.toString().trim());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    fields.add(current.toString().trim());
    return fields;
  }

  Map<String, int?> _mapColumns(List<String> headers) {
    int? find(List<String> names) {
      for (final name in names) {
        final idx = headers.indexOf(name);
        if (idx >= 0) return idx;
      }
      return null;
    }

    // Also support partial/contains matching for multi-word headers
    int? findContains(List<String> keywords) {
      for (final keyword in keywords) {
        for (var i = 0; i < headers.length; i++) {
          if (headers[i].contains(keyword)) return i;
        }
      }
      return null;
    }

    return {
      'qty': find(['qty', 'quantity', 'count']),
      'value': find(['value', 'val']),
      'device': find(['device', 'component']),
      'package': find(['package', 'footprint', 'pkg']),
      'parts': find(['parts', 'reference', 'references', 'designator', 'ref'])
          ?? findContains(['reference designator']),
      'description': find(['description', 'desc']),
      'manufacturer': find(['manufacturer', 'mfr']),
      'manufacturer_pn': find(['manufacturer part number', 'mfr part', 'mpn']),
      'vendor': find(['vendor', 'supplier']),
      'vendor_pn': find(['vendor part number', 'supplier part number']),
      'lcsc': find(['lcsc_part', 'lcsc', 'jlc_part', 'jlcpcb']),
      'digikey': find(['digikey_part', 'digikey', 'digi-key']),
      'mouser': find(['mouser_part', 'mouser']),
      'amazon': find(['amazon_part', 'amazon', 'amazon_asin', 'asin']),
    };
  }

  ParsedBomEntry? _parseRow(
      List<String> fields, Map<String, int?> colMap, List<String> headers) {
    String field(String col) {
      final idx = colMap[col];
      if (idx == null || idx >= fields.length) return '';
      return fields[idx].trim();
    }

    final value = field('value');
    final package = field('package');
    final partsStr = field('parts');
    final qtyStr = field('qty');
    final device = field('device');

    // Skip empty rows
    if (value.isEmpty && partsStr.isEmpty && device.isEmpty) return null;

    // Parse quantity — default to 1, or count reference designators
    int quantity;
    if (qtyStr.isNotEmpty) {
      quantity = int.tryParse(qtyStr) ?? 1;
    } else if (partsStr.contains(',')) {
      quantity = partsStr.split(',').length;
    } else {
      quantity = 1;
    }

    // Build supplier parts map from explicit columns
    final supplierParts = <String, String>{};
    final lcsc = field('lcsc');
    if (lcsc.isNotEmpty) supplierParts['LCSC'] = lcsc;
    final digikey = field('digikey');
    if (digikey.isNotEmpty) supplierParts['DIGIKEY'] = digikey;
    final mouser = field('mouser');
    if (mouser.isNotEmpty) supplierParts['MOUSER'] = mouser;
    final amazon = field('amazon');
    if (amazon.isNotEmpty) supplierParts['AMAZON'] = amazon;

    // Eagle's "Vendor" / "Vendor Part Number" columns are the OEM/manufacturer,
    // not a distributor. Use them as manufacturer info.
    final vendor = field('vendor');
    final vendorPn = field('vendor_pn');

    // Manufacturer: explicit column first, then fall back to Eagle "Vendor"
    final mfrPn = field('manufacturer_pn');
    final effectiveMfrPn = mfrPn.isNotEmpty ? mfrPn : (vendorPn.isNotEmpty ? vendorPn : null);
    final mfr = field('manufacturer');
    final effectiveMfr = mfr.isNotEmpty ? mfr : (vendor.isNotEmpty ? vendor : null);
    final description = field('description');

    return ParsedBomEntry(
      referenceDesignator: partsStr.isNotEmpty ? partsStr : '—',
      value: value.isNotEmpty ? value : device,
      package: package,
      quantity: quantity,
      supplierParts: supplierParts,
      description: description.isNotEmpty ? description : null,
      manufacturerPartNumber: effectiveMfrPn,
      manufacturer: effectiveMfr,
    );
  }
}
