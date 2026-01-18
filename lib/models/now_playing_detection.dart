import 'package:equatable/equatable.dart';

/// Event type for now playing events.
enum NowPlayingEventType {
  /// A record was placed on the hub.
  placed,

  /// A record was removed from the hub.
  removed;

  static NowPlayingEventType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'placed':
        return NowPlayingEventType.placed;
      case 'removed':
        return NowPlayingEventType.removed;
      default:
        return NowPlayingEventType.placed;
    }
  }
}

/// Represents a Now Playing event from a Saturday Hub.
///
/// When a record jacket is placed on or removed from the hub, the hub reads
/// the RFID tag and sends the EPC to the cloud. This model represents that event.
///
/// Maps to the `now_playing_events` table:
/// - id: UUID primary key
/// - unit_id: Serial number of the hub device
/// - epc: EPC identifier from RFID tag
/// - event_type: 'placed' or 'removed'
/// - rssi: Signal strength (optional)
/// - duration_ms: How long tag was present (only on 'removed' events)
/// - timestamp: When the event occurred
/// - created_at: When the row was inserted
class NowPlayingEvent extends Equatable {
  /// Unique identifier for this event.
  final String id;

  /// The serial number of the hub that detected this event.
  /// This maps to `consumer_devices.serial_number` to find the user.
  final String unitId;

  /// The EPC identifier read from the RFID tag.
  final String epc;

  /// The type of event (placed or removed).
  final NowPlayingEventType eventType;

  /// Signal strength of the RFID read (optional).
  final int? rssi;

  /// Duration in milliseconds the tag was present (only on removed events).
  final int? durationMs;

  /// When the event occurred.
  final DateTime timestamp;

  /// When the row was created in the database.
  final DateTime createdAt;

  const NowPlayingEvent({
    required this.id,
    required this.unitId,
    required this.epc,
    required this.eventType,
    this.rssi,
    this.durationMs,
    required this.timestamp,
    required this.createdAt,
  });

  factory NowPlayingEvent.fromJson(Map<String, dynamic> json) {
    return NowPlayingEvent(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      epc: json['epc'] as String,
      eventType: NowPlayingEventType.fromString(json['event_type'] as String),
      rssi: json['rssi'] as int?,
      durationMs: json['duration_ms'] as int?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unit_id': unitId,
      'epc': epc,
      'event_type': eventType.name,
      'rssi': rssi,
      'duration_ms': durationMs,
      'timestamp': timestamp.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Whether this is a "placed" event (record put on hub).
  bool get isPlaced => eventType == NowPlayingEventType.placed;

  /// Whether this is a "removed" event (record taken off hub).
  bool get isRemoved => eventType == NowPlayingEventType.removed;

  /// Duration as a Dart Duration object (only meaningful for removed events).
  Duration? get duration =>
      durationMs != null ? Duration(milliseconds: durationMs!) : null;

  @override
  List<Object?> get props => [
        id,
        unitId,
        epc,
        eventType,
        rssi,
        durationMs,
        timestamp,
        createdAt,
      ];
}

// Keep the old class as an alias for backward compatibility during transition
@Deprecated('Use NowPlayingEvent instead')
typedef NowPlayingDetection = NowPlayingEvent;
