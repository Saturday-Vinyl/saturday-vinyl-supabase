import 'package:saturday_app/models/unit_timer.dart';
import 'package:saturday_app/models/unit_timer_with_details.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing unit timers (active timer instances)
class UnitTimerRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get all timers for a production unit (ordered by expires_at)
  Future<List<UnitTimer>> getTimersForUnit(String unitId) async {
    try {
      AppLogger.info('Fetching timers for unit: $unitId');

      final response = await _supabase
          .from('unit_timers')
          .select()
          .eq('unit_id', unitId)
          .order('expires_at');

      final timers = (response as List)
          .map((json) => UnitTimer.fromJson(json))
          .toList();

      AppLogger.info('Found ${timers.length} timers for unit $unitId');
      return timers;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching unit timers', error, stackTrace);
      rethrow;
    }
  }

  /// Get all active timers for a production unit with timer details
  Future<List<UnitTimerWithDetails>> getActiveTimersWithDetailsForUnit(
      String unitId) async {
    try {
      AppLogger.info('Fetching active timers with details for unit: $unitId');

      final response = await _supabase
          .from('unit_timers')
          .select('*, step_timers(*)')
          .eq('unit_id', unitId)
          .eq('status', 'active')
          .order('expires_at');

      final timers = (response as List)
          .map((json) => UnitTimerWithDetails.fromJson(json))
          .toList();

      AppLogger.info(
          'Found ${timers.length} active timers with details for unit $unitId');
      return timers;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Error fetching active unit timers with details', error, stackTrace);
      rethrow;
    }
  }

  /// Get all active timers for a production unit
  Future<List<UnitTimer>> getActiveTimersForUnit(String unitId) async {
    try {
      AppLogger.info('Fetching active timers for unit: $unitId');

      final response = await _supabase
          .from('unit_timers')
          .select()
          .eq('unit_id', unitId)
          .eq('status', 'active')
          .order('expires_at');

      final timers = (response as List)
          .map((json) => UnitTimer.fromJson(json))
          .toList();

      AppLogger.info('Found ${timers.length} active timers for unit $unitId');
      return timers;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching active unit timers', error, stackTrace);
      rethrow;
    }
  }

  /// Get all active timers across all units (for global timer monitoring)
  Future<List<UnitTimer>> getAllActiveTimers() async {
    try {
      AppLogger.info('Fetching all active timers');

      final response = await _supabase
          .from('unit_timers')
          .select()
          .eq('status', 'active')
          .order('expires_at');

      final timers = (response as List)
          .map((json) => UnitTimer.fromJson(json))
          .toList();

      AppLogger.info('Found ${timers.length} active timers across all units');
      return timers;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching all active timers', error, stackTrace);
      rethrow;
    }
  }

  /// Start a timer (create a new unit timer)
  Future<UnitTimer> startTimer({
    required String unitId,
    required String stepTimerId,
    required int durationMinutes,
  }) async {
    try {
      AppLogger.info('Starting timer for unit $unitId, duration: $durationMinutes minutes');

      final now = DateTime.now().toUtc();
      final expiresAt = now.add(Duration(minutes: durationMinutes));

      final response = await _supabase
          .from('unit_timers')
          .insert({
            'unit_id': unitId,
            'step_timer_id': stepTimerId,
            'started_at': now.toIso8601String(),
            'expires_at': expiresAt.toIso8601String(),
            'status': 'active',
          })
          .select()
          .single();

      final timer = UnitTimer.fromJson(response);
      AppLogger.info('Started timer: ${timer.id}');
      return timer;
    } catch (error, stackTrace) {
      AppLogger.error('Error starting timer', error, stackTrace);
      rethrow;
    }
  }

  /// Mark a timer as completed
  Future<UnitTimer> completeTimer(String timerId) async {
    try {
      AppLogger.info('Completing timer: $timerId');

      final now = DateTime.now().toUtc();

      final response = await _supabase
          .from('unit_timers')
          .update({
            'status': 'completed',
            'completed_at': now.toIso8601String(),
          })
          .eq('id', timerId)
          .select()
          .single();

      final timer = UnitTimer.fromJson(response);
      AppLogger.info('Completed timer: ${timer.id}');
      return timer;
    } catch (error, stackTrace) {
      AppLogger.error('Error completing timer', error, stackTrace);
      rethrow;
    }
  }

  /// Cancel a timer
  Future<UnitTimer> cancelTimer(String timerId) async {
    try {
      AppLogger.info('Cancelling timer: $timerId');

      final response = await _supabase
          .from('unit_timers')
          .update({
            'status': 'cancelled',
          })
          .eq('id', timerId)
          .select()
          .single();

      final timer = UnitTimer.fromJson(response);
      AppLogger.info('Cancelled timer: ${timer.id}');
      return timer;
    } catch (error, stackTrace) {
      AppLogger.error('Error cancelling timer', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a timer
  Future<void> deleteTimer(String timerId) async {
    try {
      AppLogger.info('Deleting timer: $timerId');

      await _supabase
          .from('unit_timers')
          .delete()
          .eq('id', timerId);

      AppLogger.info('Deleted timer: $timerId');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting timer', error, stackTrace);
      rethrow;
    }
  }

  /// Get expired but still active timers (for notification purposes)
  Future<List<UnitTimer>> getExpiredActiveTimers() async {
    try {
      AppLogger.info('Fetching expired active timers');

      final now = DateTime.now().toUtc();

      final response = await _supabase
          .from('unit_timers')
          .select()
          .eq('status', 'active')
          .lt('expires_at', now.toIso8601String())
          .order('expires_at');

      final timers = (response as List)
          .map((json) => UnitTimer.fromJson(json))
          .toList();

      AppLogger.info('Found ${timers.length} expired active timers');
      return timers;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching expired active timers', error, stackTrace);
      rethrow;
    }
  }
}
