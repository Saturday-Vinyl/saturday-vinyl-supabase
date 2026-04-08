import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/models/heartbeat_chart_data.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

// ============================================================================
// State Model
// ============================================================================

class HeartbeatChartState extends Equatable {
  final ChartTimeRange timeRange;
  final Set<HeartbeatMetric> enabledMetrics;

  /// Raw data points per device (mac -> sorted list)
  final Map<String, List<HeartbeatDataPoint>> dataPoints;

  /// Data points split into contiguous segments (mac -> list of segments)
  /// Gaps > 5 minutes between heartbeats create segment boundaries.
  final Map<String, List<List<HeartbeatDataPoint>>> segments;

  /// Event markers (restarts, RFID scans)
  final List<ChartEventMarker> eventMarkers;

  /// Which metrics actually have data across all devices
  final Set<HeartbeatMetric> availableMetrics;

  final bool isLoading;
  final String? error;

  const HeartbeatChartState({
    this.timeRange = ChartTimeRange.oneHour,
    this.enabledMetrics = const {
      HeartbeatMetric.batteryLevel,
      HeartbeatMetric.freeHeap,
      HeartbeatMetric.wifiRssi,
      HeartbeatMetric.threadRssi,
    },
    this.dataPoints = const {},
    this.segments = const {},
    this.eventMarkers = const [],
    this.availableMetrics = const {},
    this.isLoading = false,
    this.error,
  });

  bool get hasData => dataPoints.values.any((pts) => pts.isNotEmpty);

  HeartbeatChartState copyWith({
    ChartTimeRange? timeRange,
    Set<HeartbeatMetric>? enabledMetrics,
    Map<String, List<HeartbeatDataPoint>>? dataPoints,
    Map<String, List<List<HeartbeatDataPoint>>>? segments,
    List<ChartEventMarker>? eventMarkers,
    Set<HeartbeatMetric>? availableMetrics,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return HeartbeatChartState(
      timeRange: timeRange ?? this.timeRange,
      enabledMetrics: enabledMetrics ?? this.enabledMetrics,
      dataPoints: dataPoints ?? this.dataPoints,
      segments: segments ?? this.segments,
      eventMarkers: eventMarkers ?? this.eventMarkers,
      availableMetrics: availableMetrics ?? this.availableMetrics,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        timeRange,
        enabledMetrics,
        dataPoints,
        segments,
        eventMarkers,
        availableMetrics,
        isLoading,
        error,
      ];
}

// ============================================================================
// Provider
// ============================================================================

final heartbeatChartProvider = StateNotifierProvider.family<
    HeartbeatChartNotifier, HeartbeatChartState, String>(
  (ref, unitId) => HeartbeatChartNotifier(ref, unitId),
);

// ============================================================================
// Notifier
// ============================================================================

class HeartbeatChartNotifier extends StateNotifier<HeartbeatChartState> {
  final Ref ref;
  final String unitId;

  /// Gap threshold: breaks in heartbeat data > this duration create line gaps
  static const gapThreshold = Duration(minutes: 5);

  List<Device> _devices = [];

  HeartbeatChartNotifier(this.ref, this.unitId)
      : super(const HeartbeatChartState());

  /// Load chart data for the given devices
  Future<void> loadData(List<Device> devices) async {
    _devices = devices;
    if (devices.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final macAddresses = devices.map((d) => d.macAddress).toList();
      final since =
          DateTime.now().subtract(state.timeRange.duration).toUtc();

      // Fetch heartbeats and RFID events in parallel
      final results = await Future.wait([
        _fetchHeartbeats(macAddresses, since),
        _fetchRfidEvents(devices, since),
      ]);

      final allPoints = results[0] as List<HeartbeatDataPoint>;
      final rfidMarkers = results[1] as List<ChartEventMarker>;

      // Group by device
      final pointsByDevice = <String, List<HeartbeatDataPoint>>{};
      for (final point in allPoints) {
        pointsByDevice.putIfAbsent(point.macAddress, () => []).add(point);
      }

      // Detect restarts and build event markers
      final restartMarkers = <ChartEventMarker>[];
      final processedByDevice = <String, List<HeartbeatDataPoint>>{};

      for (final entry in pointsByDevice.entries) {
        final mac = entry.key;
        final points = entry.value..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final processed = _detectRestarts(points, restartMarkers);
        processedByDevice[mac] = processed;
      }

      // Build segments (split at gaps)
      final segmentsByDevice = <String, List<List<HeartbeatDataPoint>>>{};
      for (final entry in processedByDevice.entries) {
        segmentsByDevice[entry.key] = _segmentDataPoints(entry.value);
      }

      // Determine which metrics have data
      final available = _detectAvailableMetrics(allPoints);

      state = state.copyWith(
        dataPoints: processedByDevice,
        segments: segmentsByDevice,
        eventMarkers: [...restartMarkers, ...rfidMarkers]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
        availableMetrics: available,
        isLoading: false,
      );

      AppLogger.info(
          'Chart loaded: ${allPoints.length} points, '
          '${restartMarkers.length} restarts, '
          '${rfidMarkers.length} RFID events');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load chart data', error, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load telemetry: $error',
      );
    }
  }

  /// Change time range and re-fetch
  Future<void> setTimeRange(ChartTimeRange range) async {
    state = state.copyWith(timeRange: range);
    await loadData(_devices);
  }

  /// Toggle a metric on/off
  void toggleMetric(HeartbeatMetric metric) {
    final updated = Set<HeartbeatMetric>.from(state.enabledMetrics);
    if (updated.contains(metric)) {
      updated.remove(metric);
    } else {
      updated.add(metric);
    }
    state = state.copyWith(enabledMetrics: updated);
  }

  // --------------------------------------------------------------------------
  // Private helpers
  // --------------------------------------------------------------------------

  Future<List<HeartbeatDataPoint>> _fetchHeartbeats(
    List<String> macAddresses,
    DateTime since,
  ) async {
    final supabase = SupabaseService.instance.client;

    final response = await supabase
        .from('device_heartbeats')
        .select(
            'created_at, mac_address, device_type, battery_level, free_heap, wifi_rssi, thread_rssi, uptime_sec, telemetry')
        .inFilter('mac_address', macAddresses)
        .eq('type', 'status')
        .gte('created_at', since.toIso8601String())
        .order('created_at')
        .limit(state.timeRange.queryLimit);

    return (response as List)
        .map((json) =>
            HeartbeatDataPoint.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChartEventMarker>> _fetchRfidEvents(
    List<Device> devices,
    DateTime since,
  ) async {
    final supabase = SupabaseService.instance.client;
    final markers = <ChartEventMarker>[];

    // Crate inventory events (for crate devices)
    final crateMacs = devices
        .where((d) => d.deviceTypeSlug == 'crate')
        .map((d) => d.macAddress)
        .toList();

    if (crateMacs.isNotEmpty) {
      try {
        final crateResponse = await supabase
            .from('crate_inventory_events')
            .select('created_at, mac_address, epc_count')
            .inFilter('mac_address', crateMacs)
            .gte('created_at', since.toIso8601String())
            .order('created_at')
            .limit(200);

        for (final json in crateResponse as List) {
          final row = json as Map<String, dynamic>;
          markers.add(ChartEventMarker(
            timestamp: DateTime.parse(row['created_at'] as String),
            type: ChartEventType.rfidScan,
            label: 'Inventory: ${row['epc_count']} tags',
            macAddress: row['mac_address'] as String?,
          ));
        }
      } catch (e) {
        AppLogger.debug('No crate_inventory_events table or query failed: $e');
      }
    }

    // Now playing events (for hub devices, keyed by unit_id)
    final hasHub = devices.any((d) => d.deviceTypeSlug == 'hub');
    if (hasHub) {
      try {
        // unit_id on now_playing_events is the unit serial
        final unitSerial = devices
            .firstWhere((d) => d.deviceTypeSlug == 'hub')
            .unitId;

        if (unitSerial != null) {
          final npResponse = await supabase
              .from('now_playing_events')
              .select('created_at, event_type, epc')
              .eq('unit_id', unitSerial)
              .gte('created_at', since.toIso8601String())
              .order('created_at')
              .limit(200);

          for (final json in npResponse as List) {
            final row = json as Map<String, dynamic>;
            final eventType = row['event_type'] as String? ?? 'scan';
            markers.add(ChartEventMarker(
              timestamp: DateTime.parse(row['created_at'] as String),
              type: ChartEventType.rfidScan,
              label: 'Record $eventType',
            ));
          }
        }
      } catch (e) {
        AppLogger.debug('No now_playing_events table or query failed: $e');
      }
    }

    return markers;
  }

  /// Detect restart events using uptime_sec, reset_reason, boot_count,
  /// and brownout_streak. Returns processed points with isRestartEvent set,
  /// and populates markers with rich context.
  List<HeartbeatDataPoint> _detectRestarts(
    List<HeartbeatDataPoint> sortedPoints,
    List<ChartEventMarker> markers,
  ) {
    if (sortedPoints.isEmpty) return sortedPoints;

    final result = <HeartbeatDataPoint>[sortedPoints.first];

    // Check first point for brownout streak
    _checkBrownoutStreak(sortedPoints.first, null, markers);

    for (var i = 1; i < sortedPoints.length; i++) {
      final prev = sortedPoints[i - 1];
      final curr = sortedPoints[i];

      // Detect restart via uptime decrease or boot_count increase
      final uptimeRestart = prev.uptimeSec != null &&
          curr.uptimeSec != null &&
          curr.uptimeSec! < prev.uptimeSec!;

      final bootCountDelta = (prev.bootCount != null && curr.bootCount != null)
          ? curr.bootCount! - prev.bootCount!
          : null;
      final bootCountRestart = bootCountDelta != null && bootCountDelta > 0;

      final isRestart = uptimeRestart || bootCountRestart;

      if (isRestart) {
        result.add(curr.copyWith(isRestartEvent: true));

        // Build a descriptive label
        final reason = curr.resetReason;
        final reasonLabel = reason != null && reason != ResetReason.unknown
            ? reason.label
            : null;

        String label;
        if (bootCountDelta != null && bootCountDelta > 1) {
          label = '${bootCountDelta}x restarts';
          if (reasonLabel != null) label += ' ($reasonLabel)';
        } else {
          label = reasonLabel != null ? 'Restart: $reasonLabel' : 'Restart';
        }

        markers.add(ChartEventMarker(
          timestamp: curr.timestamp,
          type: ChartEventType.restart,
          label: label,
          macAddress: curr.macAddress,
        ));
      } else {
        result.add(curr);
      }

      // Check for brownout streak transitions
      _checkBrownoutStreak(curr, prev, markers);
    }
    return result;
  }

  /// Detect brownout loop start/recovery between consecutive points
  void _checkBrownoutStreak(
    HeartbeatDataPoint curr,
    HeartbeatDataPoint? prev,
    List<ChartEventMarker> markers,
  ) {
    final currStreak = curr.brownoutStreak ?? 0;
    final prevStreak = prev?.brownoutStreak ?? 0;

    if (currStreak >= 2 && prevStreak < 2) {
      // Entered brownout loop
      markers.add(ChartEventMarker(
        timestamp: curr.timestamp,
        type: ChartEventType.brownoutLoop,
        label: 'Brownout loop: $currStreak consecutive',
        macAddress: curr.macAddress,
      ));
    } else if (currStreak == 0 && prevStreak >= 2) {
      // Recovered from brownout loop
      markers.add(ChartEventMarker(
        timestamp: curr.timestamp,
        type: ChartEventType.restart,
        label: 'Recovered from brownout loop',
        macAddress: curr.macAddress,
      ));
    }
  }

  /// Split sorted data points into contiguous segments.
  /// A new segment starts when the gap between consecutive points > threshold.
  List<List<HeartbeatDataPoint>> _segmentDataPoints(
    List<HeartbeatDataPoint> sortedPoints,
  ) {
    if (sortedPoints.isEmpty) return [];

    final segments = <List<HeartbeatDataPoint>>[];
    var currentSegment = <HeartbeatDataPoint>[sortedPoints.first];

    for (var i = 1; i < sortedPoints.length; i++) {
      final gap =
          sortedPoints[i].timestamp.difference(sortedPoints[i - 1].timestamp);

      if (gap > gapThreshold) {
        segments.add(currentSegment);
        currentSegment = <HeartbeatDataPoint>[sortedPoints[i]];
      } else {
        currentSegment.add(sortedPoints[i]);
      }
    }

    segments.add(currentSegment);
    return segments;
  }

  /// Determine which metrics have at least one non-null value
  Set<HeartbeatMetric> _detectAvailableMetrics(
      List<HeartbeatDataPoint> points) {
    final available = <HeartbeatMetric>{};
    for (final point in points) {
      if (point.batteryLevel != null) available.add(HeartbeatMetric.batteryLevel);
      if (point.freeHeap != null) available.add(HeartbeatMetric.freeHeap);
      if (point.wifiRssi != null) available.add(HeartbeatMetric.wifiRssi);
      if (point.threadRssi != null) available.add(HeartbeatMetric.threadRssi);
      if (available.length == HeartbeatMetric.values.length) break;
    }
    return available;
  }
}
