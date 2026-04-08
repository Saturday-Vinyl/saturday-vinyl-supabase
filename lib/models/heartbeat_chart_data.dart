import 'package:equatable/equatable.dart';

/// Metrics available for charting
enum HeartbeatMetric {
  batteryLevel('Battery', '%'),
  freeHeap('Free Heap', 'KB'),
  wifiRssi('WiFi RSSI', 'dBm'),
  threadRssi('Thread RSSI', 'dBm');

  final String label;
  final String unit;
  const HeartbeatMetric(this.label, this.unit);
}

/// Time range options for the chart
enum ChartTimeRange {
  oneHour(Duration(hours: 1), '1h', 200),
  sixHours(Duration(hours: 6), '6h', 1000),
  twentyFourHours(Duration(hours: 24), '24h', 3000);

  final Duration duration;
  final String label;
  final int queryLimit;
  const ChartTimeRange(this.duration, this.label, this.queryLimit);
}

/// A single heartbeat data point for charting
class HeartbeatDataPoint extends Equatable {
  final DateTime timestamp;
  final String macAddress;
  final String? deviceType;
  final int? batteryLevel;
  final int? freeHeap;
  final int? wifiRssi;
  final int? threadRssi;
  final int? uptimeSec;
  final bool isRestartEvent;

  // Boot diagnostics (from telemetry JSONB)
  final ResetReason? resetReason;
  final int? bootCount;
  final int? brownoutStreak;

  const HeartbeatDataPoint({
    required this.timestamp,
    required this.macAddress,
    this.deviceType,
    this.batteryLevel,
    this.freeHeap,
    this.wifiRssi,
    this.threadRssi,
    this.uptimeSec,
    this.isRestartEvent = false,
    this.resetReason,
    this.bootCount,
    this.brownoutStreak,
  });

  /// Get value for a given metric
  double? valueFor(HeartbeatMetric metric) {
    switch (metric) {
      case HeartbeatMetric.batteryLevel:
        return batteryLevel?.toDouble();
      case HeartbeatMetric.freeHeap:
        return freeHeap != null ? freeHeap! / 1024.0 : null; // bytes -> KB
      case HeartbeatMetric.wifiRssi:
        return wifiRssi?.toDouble();
      case HeartbeatMetric.threadRssi:
        return threadRssi?.toDouble();
    }
  }

  factory HeartbeatDataPoint.fromJson(
    Map<String, dynamic> json, {
    bool isRestart = false,
  }) {
    // Boot diagnostics live in the telemetry JSONB
    final telemetry = json['telemetry'] as Map<String, dynamic>?;
    final resetReasonCode = telemetry?['reset_reason'] as int?;
    final bootCount = telemetry?['boot_count'] as int?;
    final brownoutStreak = telemetry?['brownout_streak'] as int?;

    return HeartbeatDataPoint(
      timestamp: DateTime.parse(json['created_at'] as String),
      macAddress: json['mac_address'] as String,
      deviceType: json['device_type'] as String?,
      batteryLevel: json['battery_level'] as int?,
      freeHeap: json['free_heap'] as int?,
      wifiRssi: json['wifi_rssi'] as int?,
      threadRssi: json['thread_rssi'] as int?,
      uptimeSec: json['uptime_sec'] as int?,
      isRestartEvent: isRestart,
      resetReason: resetReasonCode != null
          ? ResetReason.fromCode(resetReasonCode)
          : null,
      bootCount: bootCount,
      brownoutStreak: brownoutStreak,
    );
  }

  HeartbeatDataPoint copyWith({bool? isRestartEvent}) {
    return HeartbeatDataPoint(
      timestamp: timestamp,
      macAddress: macAddress,
      deviceType: deviceType,
      batteryLevel: batteryLevel,
      freeHeap: freeHeap,
      wifiRssi: wifiRssi,
      threadRssi: threadRssi,
      uptimeSec: uptimeSec,
      isRestartEvent: isRestartEvent ?? this.isRestartEvent,
      resetReason: resetReason,
      bootCount: bootCount,
      brownoutStreak: brownoutStreak,
    );
  }

  @override
  List<Object?> get props => [
        timestamp,
        macAddress,
        deviceType,
        batteryLevel,
        freeHeap,
        wifiRssi,
        threadRssi,
        uptimeSec,
        isRestartEvent,
        resetReason,
        bootCount,
        brownoutStreak,
      ];
}

/// ESP-IDF reset reason codes
enum ResetReason {
  unknown(0, 'Unknown', ResetSeverity.warning),
  poweron(1, 'Power On', ResetSeverity.normal),
  external_(2, 'External', ResetSeverity.warning),
  software(3, 'Software', ResetSeverity.normal),
  panic(4, 'Panic', ResetSeverity.alert),
  interruptWdt(5, 'Interrupt WDT', ResetSeverity.alert),
  taskWdt(6, 'Task WDT', ResetSeverity.alert),
  wdt(7, 'WDT', ResetSeverity.alert),
  deepsleep(8, 'Deep Sleep', ResetSeverity.normal),
  brownout(9, 'Brownout', ResetSeverity.alert),
  sdio(10, 'SDIO', ResetSeverity.warning);

  final int code;
  final String label;
  final ResetSeverity severity;
  const ResetReason(this.code, this.label, this.severity);

  static ResetReason fromCode(int? code) {
    if (code == null) return ResetReason.unknown;
    return ResetReason.values.firstWhere(
      (r) => r.code == code,
      orElse: () => ResetReason.unknown,
    );
  }
}

enum ResetSeverity { normal, warning, alert }

/// Type of event marker on the chart timeline
enum ChartEventType { restart, rfidScan, brownoutLoop }

/// An event marker displayed on the chart timeline
class ChartEventMarker extends Equatable {
  final DateTime timestamp;
  final ChartEventType type;
  final String label;
  final String? macAddress;

  const ChartEventMarker({
    required this.timestamp,
    required this.type,
    required this.label,
    this.macAddress,
  });

  @override
  List<Object?> get props => [timestamp, type, label, macAddress];
}
