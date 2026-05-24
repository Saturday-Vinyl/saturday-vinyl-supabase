import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saturday_app/models/push_observability.dart';
import 'package:saturday_app/providers/unit_dashboard_provider.dart'
    show realtimeServiceProvider;
import 'package:saturday_app/repositories/push_observability_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository singleton.
final pushObservabilityRepositoryProvider =
    Provider<PushObservabilityRepository>((ref) {
  return PushObservabilityRepository();
});

// ============================================================================
// Devices
// ============================================================================

final pushDeviceFilterProvider =
    StateNotifierProvider<PushDeviceFilterNotifier, PushDeviceFilter>(
  (ref) => PushDeviceFilterNotifier(),
);

class PushDeviceFilterNotifier extends StateNotifier<PushDeviceFilter> {
  PushDeviceFilterNotifier() : super(const PushDeviceFilter());

  void setPlatform(String? platform) {
    state = state.copyWith(
      platform: platform,
      clearPlatform: platform == null,
    );
  }

  void setIsActive(bool? isActive) {
    state = state.copyWith(
      isActive: isActive,
      clearIsActive: isActive == null,
    );
  }

  void setSearch(String? query) {
    state = state.copyWith(
      searchEmail: query,
      clearSearchEmail: query == null || query.isEmpty,
    );
  }

  void reset() => state = const PushDeviceFilter();
}

final pushDevicesProvider = FutureProvider<List<PushDevice>>((ref) async {
  final filter = ref.watch(pushDeviceFilterProvider);
  final repo = ref.watch(pushObservabilityRepositoryProvider);
  return repo.listDevices(filter: filter);
});

// ============================================================================
// Activity / Deliveries (with realtime tail)
// ============================================================================

final pushDeliveryFilterProvider =
    StateNotifierProvider<PushDeliveryFilterNotifier, PushDeliveryFilter>(
  (ref) => PushDeliveryFilterNotifier(),
);

class PushDeliveryFilterNotifier extends StateNotifier<PushDeliveryFilter> {
  PushDeliveryFilterNotifier() : super(const PushDeliveryFilter());

  void setNotificationType(String? type) {
    state = state.copyWith(
      notificationType: type,
      clearNotificationType: type == null,
    );
  }

  void setStatus(PushDeliveryStatus? status) {
    state = state.copyWith(status: status, clearStatus: status == null);
  }

  void setTokenId(String? tokenId) {
    state = state.copyWith(tokenId: tokenId, clearTokenId: tokenId == null);
  }

  void setUserId(String? userId) {
    state = state.copyWith(userId: userId, clearUserId: userId == null);
  }

  void setSearch(String? query) {
    state = state.copyWith(
      searchEmail: query,
      clearSearchEmail: query == null || query.isEmpty,
    );
  }

  void setWindow(Duration window) {
    state = state.copyWith(window: window);
  }

  void reset() => state = const PushDeliveryFilter();
}

/// Paginated read of the activity feed for the current filter.
final pushDeliveriesProvider = FutureProvider<List<PushDelivery>>((ref) async {
  final filter = ref.watch(pushDeliveryFilterProvider);
  final repo = ref.watch(pushObservabilityRepositoryProvider);
  return repo.listDeliveries(filter: filter);
});

/// Live tail of recent delivery_log inserts. Keeps a ring buffer of the most
/// recent N rows. The dashboard merges this on top of the initial paginated
/// fetch so new events stream in without a full refetch.
class PushDeliveryTail {
  final List<PushDelivery> events;
  const PushDeliveryTail(this.events);
}

final pushDeliveryTailProvider =
    StateNotifierProvider<PushDeliveryTailNotifier, PushDeliveryTail>(
  (ref) => PushDeliveryTailNotifier(ref),
);

class PushDeliveryTailNotifier extends StateNotifier<PushDeliveryTail> {
  static const int _maxEvents = 100;
  final Ref ref;
  RealtimeChannel? _channel;

  PushDeliveryTailNotifier(this.ref) : super(const PushDeliveryTail([]));

  void startListening() {
    if (_channel != null) return;
    final realtime = ref.read(realtimeServiceProvider);
    _channel = realtime.subscribeToDeliveryLog(onInsert: _handleInsert);
    AppLogger.info('Started push delivery realtime tail');
  }

  Future<void> stopListening() async {
    if (_channel == null) return;
    final realtime = ref.read(realtimeServiceProvider);
    await realtime.unsubscribe(_channel!);
    _channel = null;
    AppLogger.info('Stopped push delivery realtime tail');
  }

  void clear() {
    state = const PushDeliveryTail([]);
  }

  void _handleInsert(PostgresChangePayload payload) {
    final raw = payload.newRecord;
    // The realtime payload comes from the underlying table, not the joined
    // view, so user/email/display_name/platform are not present. We surface
    // what we have and the UI can backfill on a manual refresh.
    final delivery = PushDelivery(
      id: raw['id'] as String,
      createdAt: DateTime.parse(raw['created_at'] as String).toLocal(),
      userId: raw['user_id'] as String,
      notificationType: raw['notification_type'] as String,
      sourceId: raw['source_id'] as String?,
      tokenId: raw['token_id'] as String?,
      status: PushDeliveryStatus.fromString(raw['status'] as String?),
      errorMessage: raw['error_message'] as String?,
      sentAt: raw['sent_at'] != null
          ? DateTime.parse(raw['sent_at'] as String).toLocal()
          : null,
      deliveredAt: raw['delivered_at'] != null
          ? DateTime.parse(raw['delivered_at'] as String).toLocal()
          : null,
      sentByUserId: raw['sent_by_user_id'] as String?,
    );

    final next = [delivery, ...state.events];
    if (next.length > _maxEvents) {
      next.removeRange(_maxEvents, next.length);
    }
    state = PushDeliveryTail(next);
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

// ============================================================================
// Dashboard aggregates
// ============================================================================

/// Last-24h sent/failed counts grouped by notification_type.
final pushStatsByTypeProvider = FutureProvider<List<PushTypeStats>>((ref) async {
  final repo = ref.watch(pushObservabilityRepositoryProvider);
  return repo.getStatsByType();
});

/// Hourly time-series for the last 7 days.
final pushHealthBucketsProvider =
    FutureProvider<List<PushHealthBucket>>((ref) async {
  final repo = ref.watch(pushObservabilityRepositoryProvider);
  return repo.listHealthBuckets();
});

/// Failure categories ranked by count over the last 7 days.
final pushErrorPatternsProvider =
    FutureProvider<List<PushErrorPattern>>((ref) async {
  final repo = ref.watch(pushObservabilityRepositoryProvider);
  return repo.listErrorPatterns();
});
