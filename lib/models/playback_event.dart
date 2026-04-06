import 'package:equatable/equatable.dart';

/// Represents an append-only playback event in the event log.
///
/// Events track state transitions in a playback session:
/// session_queued, playback_started, side_changed,
/// playback_stopped, session_cancelled.
class PlaybackEvent extends Equatable {
  final String id;
  final String sessionId;
  final String userId;
  final String eventType;
  final Map<String, dynamic> payload;
  final String sourceType;
  final String? sourceDeviceId;
  final DateTime createdAt;

  const PlaybackEvent({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.eventType,
    this.payload = const {},
    this.sourceType = 'app',
    this.sourceDeviceId,
    required this.createdAt,
  });

  factory PlaybackEvent.fromJson(Map<String, dynamic> json) {
    return PlaybackEvent(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      eventType: json['event_type'] as String,
      payload: json['payload'] != null
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      sourceType: json['source_type'] as String? ?? 'app',
      sourceDeviceId: json['source_device_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'event_type': eventType,
      'payload': payload,
      'source_type': sourceType,
      'source_device_id': sourceDeviceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  PlaybackEvent copyWith({
    String? id,
    String? sessionId,
    String? userId,
    String? eventType,
    Map<String, dynamic>? payload,
    String? sourceType,
    String? sourceDeviceId,
    DateTime? createdAt,
  }) {
    return PlaybackEvent(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userId: userId ?? this.userId,
      eventType: eventType ?? this.eventType,
      payload: payload ?? this.payload,
      sourceType: sourceType ?? this.sourceType,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        sessionId,
        userId,
        eventType,
        payload,
        sourceType,
        sourceDeviceId,
        createdAt,
      ];
}
