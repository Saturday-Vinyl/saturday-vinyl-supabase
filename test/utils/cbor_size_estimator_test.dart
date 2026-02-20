import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/utils/cbor_size_estimator.dart';

void main() {
  group('CborSizeEstimator', () {
    group('textStringSize', () {
      test('empty string is 1 byte', () {
        expect(CborSizeEstimator.textStringSize(''), equals(1));
      });

      test('short strings (0-23 chars) use 1-byte header', () {
        expect(CborSizeEstimator.textStringSize('v'), equals(2));
        expect(CborSizeEstimator.textStringSize('type'), equals(5));
        expect(CborSizeEstimator.textStringSize('status'), equals(7));
        expect(CborSizeEstimator.textStringSize('battery_level'), equals(14));
      });

      test('23-char string still uses 1-byte header', () {
        final str23 = 'a' * 23;
        expect(CborSizeEstimator.textStringSize(str23), equals(24));
      });

      test('24-char string uses 2-byte header', () {
        final str24 = 'a' * 24;
        expect(CborSizeEstimator.textStringSize(str24), equals(26));
      });
    });

    group('valueSize', () {
      test('integer is 3 bytes', () {
        expect(CborSizeEstimator.valueSize('integer'), equals(3));
      });

      test('number (float) is 5 bytes', () {
        expect(CborSizeEstimator.valueSize('number'), equals(5));
      });

      test('boolean is 1 byte', () {
        expect(CborSizeEstimator.valueSize('boolean'), equals(1));
      });

      test('string is 11 bytes', () {
        expect(CborSizeEstimator.valueSize('string'), equals(11));
      });

      test('unknown type defaults to 3 bytes', () {
        expect(CborSizeEstimator.valueSize('array'), equals(3));
      });
    });

    group('mapHeaderSize', () {
      test('0-23 items is 1 byte', () {
        expect(CborSizeEstimator.mapHeaderSize(0), equals(1));
        expect(CborSizeEstimator.mapHeaderSize(23), equals(1));
      });

      test('24+ items is 2 bytes', () {
        expect(CborSizeEstimator.mapHeaderSize(24), equals(2));
        expect(CborSizeEstimator.mapHeaderSize(255), equals(2));
      });
    });

    group('propertySize', () {
      test('integer property', () {
        const prop =
            SchemaPropertySize(name: 'battery_level', type: 'integer');
        // key: 1 + 13 = 14, value: 3 => 17
        expect(CborSizeEstimator.propertySize(prop), equals(17));
      });

      test('boolean property', () {
        const prop =
            SchemaPropertySize(name: 'charging', type: 'boolean');
        // key: 1 + 8 = 9, value: 1 => 10
        expect(CborSizeEstimator.propertySize(prop), equals(10));
      });

      test('float property', () {
        const prop =
            SchemaPropertySize(name: 'temperature_c', type: 'number');
        // key: 1 + 13 = 14, value: 5 => 19
        expect(CborSizeEstimator.propertySize(prop), equals(19));
      });

      test('nested object property', () {
        const prop = SchemaPropertySize(
          name: 'env',
          type: 'object',
          children: [
            SchemaPropertySize(name: 'temp', type: 'number'),
            SchemaPropertySize(name: 'humid', type: 'number'),
          ],
        );
        // key "env": 1+3 = 4
        // nested map header (2 items): 1
        // "temp": 1+4=5 key + 5 val = 10
        // "humid": 1+5=6 key + 5 val = 11
        // total: 4 + 1 + 10 + 11 = 26
        expect(CborSizeEstimator.propertySize(prop), equals(26));
      });

      test('empty object property has no nested overhead', () {
        const prop = SchemaPropertySize(
          name: 'data',
          type: 'object',
        );
        // key: 1+4=5, value treated as non-object (3 bytes default)
        expect(CborSizeEstimator.propertySize(prop), equals(8));
      });
    });

    group('estimateHeartbeatSize', () {
      test('empty properties give protocol overhead only', () {
        final est = CborSizeEstimator.estimateHeartbeatSize([]);
        expect(est.capabilityBytes, equals(0));
        // overhead: mapHeader(2) + "v"(2) + 1(1) + "type"(5) + "status"(7) = 16
        expect(est.protocolOverhead, equals(16));
        expect(est.totalBytes, equals(16));
        expect(est.fitsInSingleFrame, isTrue);
      });

      test('single integer field', () {
        const props = [
          SchemaPropertySize(name: 'battery_level', type: 'integer'),
        ];
        final est = CborSizeEstimator.estimateHeartbeatSize(props);
        expect(est.capabilityBytes, equals(17)); // 14 key + 3 value
        // overhead: mapHeader(3 items) = 1, + "v":1 (3) + "type":"status" (12) = 16
        expect(est.protocolOverhead, equals(16));
        expect(est.totalBytes, equals(33));
        expect(est.fitsInSingleFrame, isTrue);
      });

      test('two short fields fit in frame', () {
        const props = [
          SchemaPropertySize(name: 'bat', type: 'integer'),
          SchemaPropertySize(name: 'rssi', type: 'integer'),
        ];
        final est = CborSizeEstimator.estimateHeartbeatSize(props);
        // bat: 4+3=7, rssi: 5+3=8 => 15 cap + 16 overhead = 31
        expect(est.fitsInSingleFrame, isTrue);
      });

      test('three long-named fields exceed frame', () {
        // Even 3 verbose fields push past 62 bytes with conservative estimates
        const props = [
          SchemaPropertySize(name: 'battery_level', type: 'integer'),
          SchemaPropertySize(name: 'thread_rssi', type: 'integer'),
          SchemaPropertySize(name: 'rfid_tag_count', type: 'integer'),
        ];
        final est = CborSizeEstimator.estimateHeartbeatSize(props);
        // 17 + 15 + 18 = 50 cap + 16 overhead = 66 > 62
        expect(est.fitsInSingleFrame, isFalse);
      });

      test('many fields may exceed frame', () {
        const props = [
          SchemaPropertySize(name: 'battery_level', type: 'integer'),
          SchemaPropertySize(name: 'battery_mv', type: 'integer'),
          SchemaPropertySize(name: 'battery_charging', type: 'boolean'),
          SchemaPropertySize(name: 'thread_rssi', type: 'integer'),
          SchemaPropertySize(name: 'rfid_tag_count', type: 'integer'),
          SchemaPropertySize(name: 'temperature_c', type: 'number'),
          SchemaPropertySize(name: 'humidity_pct', type: 'number'),
        ];
        final est = CborSizeEstimator.estimateHeartbeatSize(props);
        // This should be tight or over the 62-byte limit
        expect(est.totalBytes, greaterThan(50));
      });
    });

    group('estimateCombinedHeartbeatSize', () {
      test('combines multiple capability property lists', () {
        const battery = [
          SchemaPropertySize(name: 'battery_level', type: 'integer'),
        ];
        const environment = [
          SchemaPropertySize(name: 'temperature_c', type: 'number'),
        ];
        final est = CborSizeEstimator.estimateCombinedHeartbeatSize(
            [battery, environment]);
        // Should equal estimating both together
        final combined = CborSizeEstimator.estimateHeartbeatSize(
            [...battery, ...environment]);
        expect(est.totalBytes, equals(combined.totalBytes));
      });

      test('empty lists give protocol overhead only', () {
        final est =
            CborSizeEstimator.estimateCombinedHeartbeatSize([[], []]);
        expect(est.capabilityBytes, equals(0));
        expect(est.totalBytes, equals(16));
      });
    });

    group('parseHeartbeatSchema', () {
      test('parses valid schema', () {
        final schema = {
          'type': 'object',
          'properties': {
            'battery_level': {'type': 'integer'},
            'temperature_c': {'type': 'number'},
            'charging': {'type': 'boolean'},
          },
        };
        final props = CborSizeEstimator.parseHeartbeatSchema(schema);
        expect(props.length, equals(3));
        expect(props[0].name, equals('battery_level'));
        expect(props[0].type, equals('integer'));
      });

      test('returns empty for empty schema', () {
        expect(CborSizeEstimator.parseHeartbeatSchema({}), isEmpty);
      });

      test('returns empty for schema without properties', () {
        final schema = {'type': 'object'};
        expect(CborSizeEstimator.parseHeartbeatSchema(schema), isEmpty);
      });

      test('handles nested object properties', () {
        final schema = {
          'type': 'object',
          'properties': {
            'env': {
              'type': 'object',
              'properties': {
                'temp': {'type': 'number'},
              },
            },
          },
        };
        final props = CborSizeEstimator.parseHeartbeatSchema(schema);
        expect(props.length, equals(1));
        expect(props[0].type, equals('object'));
        expect(props[0].children.length, equals(1));
        expect(props[0].children[0].name, equals('temp'));
      });
    });

    group('CborSizeEstimate', () {
      test('severity ok at low usage', () {
        const est =
            CborSizeEstimate(capabilityBytes: 20, protocolOverhead: 16);
        expect(est.severity, equals(CborSizeSeverity.ok));
        expect(est.fitsInSingleFrame, isTrue);
        expect(est.remainingBytes, equals(26));
      });

      test('severity warning at medium usage', () {
        // 51/62 = 82%
        const est =
            CborSizeEstimate(capabilityBytes: 35, protocolOverhead: 16);
        expect(est.severity, equals(CborSizeSeverity.warning));
      });

      test('severity danger at high usage', () {
        // 56/62 = 90%
        const est =
            CborSizeEstimate(capabilityBytes: 40, protocolOverhead: 16);
        expect(est.severity, equals(CborSizeSeverity.danger));
      });

      test('severity danger when over budget', () {
        const est =
            CborSizeEstimate(capabilityBytes: 50, protocolOverhead: 16);
        expect(est.fitsInSingleFrame, isFalse);
        expect(est.remainingBytes, lessThan(0));
        expect(est.severity, equals(CborSizeSeverity.danger));
      });

      test('usageRatio computes correctly', () {
        const est =
            CborSizeEstimate(capabilityBytes: 15, protocolOverhead: 16);
        expect(est.usageRatio, equals(31 / 62));
      });
    });
  });
}
