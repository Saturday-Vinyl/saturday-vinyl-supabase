import 'package:saturday_app/models/unit_timer.dart';

/// UnitTimer with associated StepTimer details
/// This model combines data from both unit_timers and step_timers tables
class UnitTimerWithDetails {
  final UnitTimer unitTimer;
  final String timerName;
  final int durationMinutes;

  const UnitTimerWithDetails({
    required this.unitTimer,
    required this.timerName,
    required this.durationMinutes,
  });

  /// Create from joined query result
  factory UnitTimerWithDetails.fromJson(Map<String, dynamic> json) {
    return UnitTimerWithDetails(
      unitTimer: UnitTimer.fromJson(json),
      timerName: json['step_timers']?['timer_name'] as String? ?? 'Unknown Timer',
      durationMinutes: json['step_timers']?['duration_minutes'] as int? ?? 0,
    );
  }

  /// Get duration as a formatted string (e.g., "15 min", "1 hr 30 min")
  String get durationFormatted {
    if (durationMinutes < 60) {
      return '$durationMinutes min';
    }

    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }
}
