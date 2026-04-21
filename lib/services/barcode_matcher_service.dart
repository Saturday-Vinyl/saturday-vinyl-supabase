import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/models/supplier_part.dart';
import 'package:saturday_app/repositories/parts_repository.dart';
import 'package:saturday_app/repositories/supplier_parts_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Metadata extracted from a structured barcode (e.g., DigiKey DataMatrix)
class ParsedBarcodeData {
  /// Manufacturer / supplier part number (DigiKey 1P field)
  final String? manufacturerPartNumber;

  /// Distributor's own part number (DigiKey 30P field, e.g., "732-8660-1-ND")
  final String? distributorPartNumber;

  /// Quantity encoded in the barcode (DigiKey Q field)
  final double? quantity;

  /// Purchase order reference (DigiKey K field)
  final String? purchaseOrder;

  /// Sales order number (DigiKey 1K field)
  final String? salesOrder;

  /// Country of origin (DigiKey 4L field)
  final String? countryOfOrigin;

  /// Manufacturer date code (DigiKey 9D field)
  final String? dateCode;

  /// Manufacturer lot code (DigiKey 1T field)
  final String? lotCode;

  /// Which supplier format was detected
  final String? detectedFormat;

  const ParsedBarcodeData({
    this.manufacturerPartNumber,
    this.distributorPartNumber,
    this.quantity,
    this.purchaseOrder,
    this.salesOrder,
    this.countryOfOrigin,
    this.dateCode,
    this.lotCode,
    this.detectedFormat,
  });

  bool get isEmpty =>
      manufacturerPartNumber == null && distributorPartNumber == null;
}

/// Result of a barcode matching attempt
class BarcodeMatchResult {
  final SupplierPart supplierPart;
  final Part part;

  /// Parsed metadata from the barcode (quantity, lot code, etc.)
  final ParsedBarcodeData? parsedData;

  const BarcodeMatchResult({
    required this.supplierPart,
    required this.part,
    this.parsedData,
  });
}

/// Service that matches scanned barcodes to supplier parts and inventory parts.
///
/// Matching strategy (in order):
/// 1. Exact match on `supplier_parts.barcode_value`
/// 2. Parse structured supplier formats (DigiKey DataMatrix per EIGP 114.2018,
///    LCSC barcodes) and match extracted identifiers against `supplier_parts.supplier_sku`
/// 3. Try the raw barcode value as a SKU directly
/// 4. Return null if no match found
class BarcodeMatcherService {
  final _supplierPartsRepo = SupplierPartsRepository();
  final _partsRepo = PartsRepository();

  /// Attempt to match a raw barcode string to a part in inventory.
  Future<BarcodeMatchResult?> match(String rawBarcode) async {
    final cleaned = rawBarcode.trim();
    if (cleaned.isEmpty) return null;

    AppLogger.info('BarcodeMatcherService: matching "$cleaned"');

    // Parse structured data first (we'll use it for matching and metadata)
    final parsed = _parseStructuredBarcode(cleaned);

    // Strategy 1: Exact barcode_value match
    var supplierPart = await _supplierPartsRepo.findByBarcode(cleaned);
    if (supplierPart != null) {
      return _resolvePartForSupplierPart(supplierPart, parsedData: parsed);
    }

    // Strategy 2: Match using parsed identifiers from structured barcodes
    if (parsed != null && !parsed.isEmpty) {
      // Try distributor part number first (e.g., DigiKey "732-8660-1-ND")
      // Users are most likely to store the distributor PN as their supplier SKU
      if (parsed.distributorPartNumber != null) {
        supplierPart = await _supplierPartsRepo
            .findBySupplierSku(parsed.distributorPartNumber!);
        if (supplierPart != null) {
          return _resolvePartForSupplierPart(supplierPart, parsedData: parsed);
        }
      }

      // Try manufacturer part number (e.g., "860010672008")
      if (parsed.manufacturerPartNumber != null) {
        supplierPart = await _supplierPartsRepo
            .findBySupplierSku(parsed.manufacturerPartNumber!);
        if (supplierPart != null) {
          return _resolvePartForSupplierPart(supplierPart, parsedData: parsed);
        }
      }
    }

    // Strategy 3: Try the raw value as a SKU directly
    supplierPart = await _supplierPartsRepo.findBySupplierSku(cleaned);
    if (supplierPart != null) {
      return _resolvePartForSupplierPart(supplierPart, parsedData: parsed);
    }

    AppLogger.info('BarcodeMatcherService: no match found for "$cleaned"');
    return null;
  }

  Future<BarcodeMatchResult?> _resolvePartForSupplierPart(
    SupplierPart supplierPart, {
    ParsedBarcodeData? parsedData,
  }) async {
    try {
      final part = await _partsRepo.getPart(supplierPart.partId);
      if (part == null) {
        AppLogger.warning(
            'BarcodeMatcherService: found supplier_part ${supplierPart.id} but part ${supplierPart.partId} not found');
        return null;
      }
      AppLogger.info(
          'BarcodeMatcherService: matched to part "${part.name}" via supplier SKU "${supplierPart.supplierSku}"');
      return BarcodeMatchResult(
        supplierPart: supplierPart,
        part: part,
        parsedData: parsedData,
      );
    } catch (e) {
      AppLogger.error('BarcodeMatcherService: error resolving part', e,
          StackTrace.current);
      return null;
    }
  }

  /// Parse a barcode string to extract structured data without matching.
  /// Returns null if the barcode is not a recognized structured format.
  ParsedBarcodeData? parseBarcode(String barcode) =>
      _parseStructuredBarcode(barcode.trim());

  /// Parse structured barcode formats to extract identifiers and metadata.
  ///
  /// Supported formats:
  /// - DigiKey 2D DataMatrix (EIGP 114.2018 / ISO/IEC 15434):
  ///   GS (0x1D) delimited fields with identifiers like 1P, 30P, Q, K, etc.
  /// - LCSC: extract `C\d+` pattern from barcode content
  ParsedBarcodeData? _parseStructuredBarcode(String barcode) {
    // DigiKey DataMatrix: uses ASCII GS (0x1D) and/or RS (0x1E) as field separators
    // Header is [)>\x1E06\x1D followed by fields
    if (barcode.contains('\x1E') ||
        barcode.contains('\x1D') ||
        barcode.startsWith('[)>')) {
      return _parseEciaDataMatrix(barcode);
    }

    // LCSC part number pattern: starts with C followed by digits
    final lcscMatch = RegExp(r'\bC(\d{3,})\b').firstMatch(barcode);
    if (lcscMatch != null) {
      return ParsedBarcodeData(
        distributorPartNumber: 'C${lcscMatch.group(1)}',
        detectedFormat: 'LCSC',
      );
    }

    return null;
  }

  /// Parse ECIA EIGP 114.2018 DataMatrix barcode (used by DigiKey, Mouser, etc.)
  ///
  /// Format per the standard (ISO/IEC 15434 envelope):
  /// `[)>\x1E06\x1D` followed by GS-delimited fields:
  ///   P    = Customer reference / PO line
  ///   1P   = Manufacturer/supplier part number
  ///   30P  = Distributor part number (e.g., DigiKey PN "732-8660-1-ND")
  ///   K    = Purchase order
  ///   1K   = Sales order number
  ///   10K  = Invoice number
  ///   Q    = Quantity
  ///   9D   = Date code
  ///   1T   = Lot code
  ///   4L   = Country of origin (ISO 3166)
  ///   12Z  = DigiKey internal product ID
  ///
  /// USB keyboard scanners often strip the GS/RS control characters, so we
  /// also support a regex-based fallback that splits on known field identifiers.
  ParsedBarcodeData? _parseEciaDataMatrix(String barcode) {
    try {
      // Split by both RS and GS separators
      final fields = barcode.split(RegExp('[\x1D\x1E]'));

      // If we got more than a couple of fields, delimiters were present
      if (fields.length > 2) {
        return _parseEciaFields(fields);
      }

      // Fallback: USB scanners strip GS/RS chars — parse without delimiters
      // Strip the [)> header and format number (e.g. "06")
      var raw = barcode;
      if (raw.startsWith('[)>')) {
        raw = raw.substring(3);
      }
      // Strip leading format number (1-2 digits)
      raw = raw.replaceFirst(RegExp(r'^\d{1,2}'), '');

      // Use regex to split on known ECIA field identifiers.
      // Order: longest prefixes first to avoid false matches.
      // The lookahead finds the next field identifier or end-of-string.
      const idPattern =
          r'30P|20Z|13Z|12Z|11Z|10K|1P|1K|1T|9D|4L|Q(?=\d)|K|P';
      final regex = RegExp('($idPattern)(.*?)(?=(?:$idPattern)|\$)');
      final matches = regex.allMatches(raw).toList();

      if (matches.isEmpty) return null;

      final regexFields =
          matches.map((m) => '${m.group(1)}${m.group(2)}').toList();
      return _parseEciaFields(regexFields);
    } catch (e) {
      AppLogger.warning(
          'BarcodeMatcherService: failed to parse ECIA DataMatrix: $e');
    }
    return null;
  }

  /// Extract data from a list of ECIA field strings (e.g. "30P450-1662-ND").
  ParsedBarcodeData? _parseEciaFields(List<String> fields) {
    String? manufacturerPn;
    String? distributorPn;
    double? quantity;
    String? purchaseOrder;
    String? salesOrder;
    String? countryOfOrigin;
    String? dateCode;
    String? lotCode;

    for (final field in fields) {
      // Order matters: check longer prefixes first to avoid false matches
      // (e.g., "30P" before "P", "10K" before "1K" before "K")
      if (field.startsWith('30P')) {
        distributorPn = field.substring(3).trim();
      } else if (field.startsWith('1P')) {
        manufacturerPn = field.substring(2).trim();
      } else if (field.startsWith('10K')) {
        // Invoice — skip for now
      } else if (field.startsWith('1K')) {
        salesOrder = field.substring(2).trim();
      } else if (field.startsWith('1T')) {
        lotCode = field.substring(2).trim();
      } else if (field.startsWith('9D')) {
        dateCode = field.substring(2).trim();
      } else if (field.startsWith('4L')) {
        countryOfOrigin = field.substring(2).trim();
      } else if (field.startsWith('Q')) {
        final qStr = field.substring(1).trim();
        quantity = double.tryParse(qStr);
      } else if (field.startsWith('K')) {
        purchaseOrder = field.substring(1).trim();
      }
      // P (customer ref), 11Z, 12Z, 13Z, 20Z — not useful for matching
    }

    if (manufacturerPn == null && distributorPn == null && quantity == null) {
      return null;
    }

    AppLogger.info(
        'BarcodeMatcherService: parsed ECIA barcode — '
        'mfr: $manufacturerPn, dist: $distributorPn, qty: $quantity');

    return ParsedBarcodeData(
      manufacturerPartNumber:
          manufacturerPn?.isNotEmpty == true ? manufacturerPn : null,
      distributorPartNumber:
          distributorPn?.isNotEmpty == true ? distributorPn : null,
      quantity: quantity,
      purchaseOrder:
          purchaseOrder?.isNotEmpty == true ? purchaseOrder : null,
      salesOrder: salesOrder?.isNotEmpty == true ? salesOrder : null,
      countryOfOrigin:
          countryOfOrigin?.isNotEmpty == true ? countryOfOrigin : null,
      dateCode: dateCode?.isNotEmpty == true ? dateCode : null,
      lotCode: lotCode?.isNotEmpty == true ? lotCode : null,
      detectedFormat: 'DigiKey/ECIA',
    );
  }
}
