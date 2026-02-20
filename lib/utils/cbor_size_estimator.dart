/// CBOR heartbeat payload size estimator for Thread mesh devices.
///
/// Estimates the encoded CBOR size of a heartbeat payload based on
/// capability heartbeat schema properties. Used to verify payloads
/// fit within the ~62 byte single 802.15.4 frame budget.
///
/// Encoding sizes follow RFC 8949 (CBOR) exactly:
/// - Text string: 1-2 byte header + N content bytes
/// - Unsigned/negative int: 1-5 bytes
/// - Boolean: 1 byte
/// - Float32: 5 bytes
/// - Map header: 1-2 bytes
class CborSizeEstimator {
  CborSizeEstimator._();

  /// Maximum single-frame CoAP payload over 802.15.4.
  static const int maxSingleFrameBytes = 62;

  /// CBOR encoded size of a text string (key or value).
  static int textStringSize(String text) {
    final length = text.length;
    if (length <= 23) return 1 + length;
    if (length <= 255) return 2 + length;
    return 3 + length;
  }

  /// Estimated CBOR value size by JSON Schema type.
  ///
  /// Uses conservative "typical worst-case" values:
  /// - integer: 3 bytes (covers 0-65535, the common sensor range)
  /// - number: 5 bytes (float32)
  /// - boolean: 1 byte
  /// - string: 11 bytes (1-byte header + ~10 chars)
  static int valueSize(String type) {
    switch (type) {
      case 'integer':
        return 3;
      case 'number':
        return 5;
      case 'boolean':
        return 1;
      case 'string':
        return 11;
      default:
        return 3;
    }
  }

  /// CBOR map header size for a given number of entries.
  static int mapHeaderSize(int itemCount) {
    if (itemCount <= 23) return 1;
    return 2;
  }

  /// Estimated CBOR size of a single schema property (key + value).
  ///
  /// For object types, recursively estimates the nested map.
  static int propertySize(SchemaPropertySize property) {
    final keyBytes = textStringSize(property.name);

    if (property.type == 'object' && property.children.isNotEmpty) {
      final childrenBytes = property.children.fold<int>(
        mapHeaderSize(property.children.length),
        (sum, child) => sum + propertySize(child),
      );
      return keyBytes + childrenBytes;
    }

    return keyBytes + valueSize(property.type);
  }

  /// Estimates total CBOR heartbeat payload size for capability fields.
  ///
  /// Includes protocol overhead: map header + `"v":1` + `"type":"status"`.
  static CborSizeEstimate estimateHeartbeatSize(
    List<SchemaPropertySize> properties,
  ) {
    // Protocol fields: "v" and "type", plus all capability fields
    final totalFieldCount = 2 + properties.length;

    final protocolOverhead = mapHeaderSize(totalFieldCount) +
        textStringSize('v') +
        1 + // value: unsigned int 1
        textStringSize('type') +
        textStringSize('status');

    final capabilityBytes = properties.fold<int>(
      0,
      (sum, prop) => sum + propertySize(prop),
    );

    return CborSizeEstimate(
      capabilityBytes: capabilityBytes,
      protocolOverhead: protocolOverhead,
    );
  }

  /// Estimates total size for multiple capabilities combined.
  static CborSizeEstimate estimateCombinedHeartbeatSize(
    List<List<SchemaPropertySize>> capabilityPropertyLists,
  ) {
    final allProperties =
        capabilityPropertyLists.expand((list) => list).toList();
    return estimateHeartbeatSize(allProperties);
  }

  /// Parses a heartbeat JSON Schema into [SchemaPropertySize] objects.
  ///
  /// Expects the standard JSON Schema format:
  /// ```json
  /// {"type": "object", "properties": {"field": {"type": "integer"}}}
  /// ```
  static List<SchemaPropertySize> parseHeartbeatSchema(
    Map<String, dynamic> schema,
  ) {
    if (schema.isEmpty) return [];
    final properties = schema['properties'] as Map<String, dynamic>?;
    if (properties == null) return [];

    return properties.entries.map((entry) {
      final fieldSchema = entry.value as Map<String, dynamic>;
      final type = fieldSchema['type']?.toString() ?? 'string';
      List<SchemaPropertySize> children = [];

      if (type == 'object' && fieldSchema['properties'] != null) {
        children = parseHeartbeatSchema(fieldSchema);
      }

      return SchemaPropertySize(
        name: entry.key,
        type: type,
        children: children,
      );
    }).toList();
  }
}

/// Lightweight data class for CBOR size estimation input.
class SchemaPropertySize {
  final String name;
  final String type;
  final List<SchemaPropertySize> children;

  const SchemaPropertySize({
    required this.name,
    required this.type,
    this.children = const [],
  });
}

/// Result of a CBOR size estimation.
class CborSizeEstimate {
  final int capabilityBytes;
  final int protocolOverhead;

  const CborSizeEstimate({
    required this.capabilityBytes,
    required this.protocolOverhead,
  });

  int get totalBytes => capabilityBytes + protocolOverhead;

  int get maxBytes => CborSizeEstimator.maxSingleFrameBytes;

  int get remainingBytes => maxBytes - totalBytes;

  bool get fitsInSingleFrame => totalBytes <= maxBytes;

  double get usageRatio => maxBytes > 0 ? totalBytes / maxBytes : 0.0;

  CborSizeSeverity get severity {
    if (usageRatio <= 0.65) return CborSizeSeverity.ok;
    if (usageRatio <= 0.85) return CborSizeSeverity.warning;
    return CborSizeSeverity.danger;
  }
}

enum CborSizeSeverity { ok, warning, danger }
