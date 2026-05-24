import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saturday_app/models/push_observability.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Filters for the activity log query.
class PushDeliveryFilter {
  final String? notificationType;
  final PushDeliveryStatus? status;
  final String? userId;
  final String? tokenId;
  final String? searchEmail;
  final Duration window;

  const PushDeliveryFilter({
    this.notificationType,
    this.status,
    this.userId,
    this.tokenId,
    this.searchEmail,
    this.window = const Duration(hours: 24),
  });

  PushDeliveryFilter copyWith({
    String? notificationType,
    PushDeliveryStatus? status,
    String? userId,
    String? tokenId,
    String? searchEmail,
    Duration? window,
    bool clearNotificationType = false,
    bool clearStatus = false,
    bool clearUserId = false,
    bool clearTokenId = false,
    bool clearSearchEmail = false,
  }) {
    return PushDeliveryFilter(
      notificationType:
          clearNotificationType ? null : (notificationType ?? this.notificationType),
      status: clearStatus ? null : (status ?? this.status),
      userId: clearUserId ? null : (userId ?? this.userId),
      tokenId: clearTokenId ? null : (tokenId ?? this.tokenId),
      searchEmail: clearSearchEmail ? null : (searchEmail ?? this.searchEmail),
      window: window ?? this.window,
    );
  }
}

/// Filters for the devices table.
class PushDeviceFilter {
  final String? platform;
  final bool? isActive;
  final String? searchEmail;

  const PushDeviceFilter({
    this.platform,
    this.isActive,
    this.searchEmail,
  });

  PushDeviceFilter copyWith({
    String? platform,
    bool? isActive,
    String? searchEmail,
    bool clearPlatform = false,
    bool clearIsActive = false,
    bool clearSearchEmail = false,
  }) {
    return PushDeviceFilter(
      platform: clearPlatform ? null : (platform ?? this.platform),
      isActive: clearIsActive ? null : (isActive ?? this.isActive),
      searchEmail: clearSearchEmail ? null : (searchEmail ?? this.searchEmail),
    );
  }
}

/// Reads admin push observability views. All queries depend on the migration
/// 20260522120000_admin_push_observability.sql and require admin RLS.
class PushObservabilityRepository {
  final _supabase = SupabaseService.instance.client;

  /// Devices, sorted by recent failure count desc then last_used desc.
  Future<List<PushDevice>> listDevices({
    PushDeviceFilter filter = const PushDeviceFilter(),
    int limit = 500,
  }) async {
    try {
      var query = _supabase.from('admin_push_devices').select();

      if (filter.platform != null) {
        query = query.eq('platform', filter.platform!);
      }
      if (filter.isActive != null) {
        query = query.eq('is_active', filter.isActive!);
      }
      if (filter.searchEmail != null && filter.searchEmail!.isNotEmpty) {
        final s = filter.searchEmail!;
        query = query.or('email.ilike.%$s%,display_name.ilike.%$s%');
      }

      final response = await query
          .order('failed_7d', ascending: false)
          .order('last_used_at', ascending: false, nullsFirst: false)
          .limit(limit);

      return (response as List)
          .map((j) => PushDevice.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to list push devices', error, stackTrace);
      rethrow;
    }
  }

  /// Recent delivery attempts matching [filter], newest first.
  Future<List<PushDelivery>> listDeliveries({
    PushDeliveryFilter filter = const PushDeliveryFilter(),
    int limit = 200,
  }) async {
    try {
      final since = DateTime.now().toUtc().subtract(filter.window);
      var query = _supabase
          .from('admin_push_deliveries')
          .select()
          .gte('created_at', since.toIso8601String());

      if (filter.notificationType != null) {
        query = query.eq('notification_type', filter.notificationType!);
      }
      if (filter.status != null) {
        query = query.eq('status', filter.status!.value);
      }
      if (filter.userId != null) {
        query = query.eq('user_id', filter.userId!);
      }
      if (filter.tokenId != null) {
        query = query.eq('token_id', filter.tokenId!);
      }
      if (filter.searchEmail != null && filter.searchEmail!.isNotEmpty) {
        final s = filter.searchEmail!;
        query = query.or('email.ilike.%$s%,display_name.ilike.%$s%');
      }

      final response =
          await query.order('created_at', ascending: false).limit(limit);

      return (response as List)
          .map((j) => PushDelivery.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to list push deliveries', error, stackTrace);
      rethrow;
    }
  }

  /// Hourly health buckets for the last 7 days.
  Future<List<PushHealthBucket>> listHealthBuckets() async {
    try {
      final response = await _supabase
          .from('admin_push_health_by_type')
          .select()
          .order('bucket_hour', ascending: true);

      return (response as List)
          .map((j) => PushHealthBucket.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to list health buckets', error, stackTrace);
      rethrow;
    }
  }

  /// Error categories ranked by failure count over the last 7 days.
  /// The view groups by hour; we collapse to per-category totals client-side
  /// so the dashboard table reads "X failures across Y tokens since first_seen".
  Future<List<PushErrorPattern>> listErrorPatterns() async {
    try {
      final response =
          await _supabase.from('admin_push_error_patterns').select();
      final rows = (response as List)
          .map((j) => PushErrorPattern.fromJson(j as Map<String, dynamic>))
          .toList();

      final byKey = <String, PushErrorPattern>{};
      for (final r in rows) {
        final key = '${r.notificationType}|${r.errorCategory}';
        final existing = byKey[key];
        if (existing == null) {
          byKey[key] = r;
        } else {
          byKey[key] = PushErrorPattern(
            notificationType: existing.notificationType,
            errorCategory: existing.errorCategory,
            n: existing.n + r.n,
            firstSeen: existing.firstSeen.isBefore(r.firstSeen)
                ? existing.firstSeen
                : r.firstSeen,
            lastSeen: existing.lastSeen.isAfter(r.lastSeen)
                ? existing.lastSeen
                : r.lastSeen,
            affectedTokens:
                existing.affectedTokens + r.affectedTokens, // approx upper bound
            affectedUsers:
                existing.affectedUsers + r.affectedUsers, // approx upper bound
          );
        }
      }

      final collapsed = byKey.values.toList()
        ..sort((a, b) => b.n.compareTo(a.n));
      return collapsed;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to list error patterns', error, stackTrace);
      rethrow;
    }
  }

  /// Send an admin-initiated free-form push to a single token via the
  /// `send-test-notification` edge function. The function logs the attempt
  /// in `notification_delivery_log` with `notification_type='admin_test'` and
  /// `sent_by_user_id` = the calling admin.
  ///
  /// Throws [PushRetryException] (reused since the shape is identical) if the
  /// edge function rejects the request (bad input, inactive token, etc.).
  Future<PushRetryResult> sendTestNotification({
    required String tokenId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-test-notification',
        body: {
          'token_id': tokenId,
          'title': title,
          'body': body,
          if (data != null) 'data': data,
        },
      );

      final raw = response.data;
      if (raw is! Map) {
        throw const PushRetryException(
          'Unexpected response from send-test-notification',
        );
      }
      final responseData = Map<String, dynamic>.from(raw);

      return PushRetryResult(
        success: responseData['success'] == true,
        deliveryLogId: responseData['delivery_log_id'] as String?,
        error: responseData['error'] as String?,
        errorCategory: responseData['error_category'] as String?,
      );
    } on FunctionException catch (error, stackTrace) {
      final details = error.details;
      String message;
      if (details is Map && details['error'] is String) {
        message = details['error'] as String;
      } else {
        message = error.reasonPhrase ?? 'Test send failed (HTTP ${error.status})';
      }
      AppLogger.error('Test send rejected by edge function: $message',
          error, stackTrace);
      throw PushRetryException(message);
    } on PushRetryException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to send test notification to token $tokenId',
          error, stackTrace);
      throw PushRetryException(error.toString());
    }
  }

  /// Re-send a previously-failed (or just to-be-replayed) delivery via the
  /// `retry-notification` edge function. The function reconstructs the
  /// original payload server-side and inserts a NEW delivery_log row marked
  /// with `sent_by_user_id` = the calling admin. The original row stays put.
  ///
  /// v1 supports `now_playing` only; other types throw a [PushRetryException]
  /// with the server's reason.
  Future<PushRetryResult> retryNotification(String deliveryLogId) async {
    try {
      final response = await _supabase.functions.invoke(
        'retry-notification',
        body: {'delivery_log_id': deliveryLogId},
      );

      final raw = response.data;
      if (raw is! Map) {
        throw const PushRetryException(
          'Unexpected response from retry-notification',
        );
      }
      final data = Map<String, dynamic>.from(raw);

      return PushRetryResult(
        success: data['success'] == true,
        deliveryLogId: data['delivery_log_id'] as String?,
        error: data['error'] as String?,
        errorCategory: data['error_category'] as String?,
      );
    } on FunctionException catch (error, stackTrace) {
      // functions.invoke throws on 4xx/5xx with the body in `details`. The
      // server returns `{ error: "<human message>" }` so we surface that
      // directly instead of the verbose FunctionException.toString().
      final details = error.details;
      String message;
      if (details is Map && details['error'] is String) {
        message = details['error'] as String;
      } else {
        message = error.reasonPhrase ?? 'Retry failed (HTTP ${error.status})';
      }
      AppLogger.error('Retry rejected by edge function: $message',
          error, stackTrace);
      throw PushRetryException(message);
    } on PushRetryException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to retry notification $deliveryLogId',
          error, stackTrace);
      throw PushRetryException(error.toString());
    }
  }

  /// Aggregate sent/failed counts for the last [window], grouped by type.
  /// Computed from the deliveries view client-side so we don't need a separate
  /// RPC.
  Future<List<PushTypeStats>> getStatsByType({
    Duration window = const Duration(hours: 24),
  }) async {
    try {
      final since = DateTime.now().toUtc().subtract(window);
      final response = await _supabase
          .from('admin_push_deliveries')
          .select('notification_type, status')
          .gte('created_at', since.toIso8601String());

      final agg = <String, _MutableStats>{};
      for (final row in response as List) {
        final m = row as Map<String, dynamic>;
        final type = m['notification_type'] as String;
        final status = m['status'] as String?;
        final stats = agg.putIfAbsent(type, () => _MutableStats());
        if (status == 'sent' || status == 'delivered') {
          stats.sent++;
        } else if (status == 'failed') {
          stats.failed++;
        }
      }

      final result = agg.entries
          .map((e) => PushTypeStats(
                notificationType: e.key,
                sent: e.value.sent,
                failed: e.value.failed,
              ))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));
      return result;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get stats by type', error, stackTrace);
      rethrow;
    }
  }
}

class _MutableStats {
  int sent = 0;
  int failed = 0;
}

class PushRetryResult {
  final bool success;
  final String? deliveryLogId;
  final String? error;
  final String? errorCategory;

  const PushRetryResult({
    required this.success,
    this.deliveryLogId,
    this.error,
    this.errorCategory,
  });
}

class PushRetryException implements Exception {
  final String message;
  const PushRetryException(this.message);

  @override
  String toString() => message;
}

class PushTypeStats {
  final String notificationType;
  final int sent;
  final int failed;

  const PushTypeStats({
    required this.notificationType,
    required this.sent,
    required this.failed,
  });

  int get total => sent + failed;
  double get failureRate => total == 0 ? 0 : failed / total;
}
