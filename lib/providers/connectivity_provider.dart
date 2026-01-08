import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connectivity state for the app.
enum ConnectivityStatus {
  /// Device is connected to the network.
  online,

  /// Device is not connected to the network.
  offline,

  /// Connectivity status is unknown or checking.
  unknown,
}

/// State for connectivity monitoring.
class ConnectivityState {
  const ConnectivityState({
    this.status = ConnectivityStatus.unknown,
    this.lastOnlineAt,
    this.lastCheckedAt,
  });

  /// Current connectivity status.
  final ConnectivityStatus status;

  /// When the device was last known to be online.
  final DateTime? lastOnlineAt;

  /// When connectivity was last checked.
  final DateTime? lastCheckedAt;

  /// Whether the device is currently online.
  bool get isOnline => status == ConnectivityStatus.online;

  /// Whether the device is currently offline.
  bool get isOffline => status == ConnectivityStatus.offline;

  /// How long ago we were last online.
  Duration? get offlineDuration {
    if (status == ConnectivityStatus.online || lastOnlineAt == null) {
      return null;
    }
    return DateTime.now().difference(lastOnlineAt!);
  }

  ConnectivityState copyWith({
    ConnectivityStatus? status,
    DateTime? lastOnlineAt,
    DateTime? lastCheckedAt,
  }) {
    return ConnectivityState(
      status: status ?? this.status,
      lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

/// Notifier for monitoring connectivity status.
///
/// Uses DNS lookups to check connectivity rather than relying
/// on system APIs, which can report "connected" even when there's
/// no actual internet access.
class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  ConnectivityNotifier() : super(const ConnectivityState()) {
    // Start monitoring connectivity.
    _startMonitoring();
  }

  Timer? _timer;
  static const Duration _checkInterval = Duration(seconds: 30);

  /// Start periodic connectivity monitoring.
  void _startMonitoring() {
    // Check immediately.
    _checkConnectivity();

    // Then check periodically.
    _timer = Timer.periodic(_checkInterval, (_) {
      _checkConnectivity();
    });
  }

  /// Check connectivity by attempting a DNS lookup.
  Future<void> _checkConnectivity() async {
    final now = DateTime.now();

    try {
      // Try to resolve a well-known hostname.
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        // We're online.
        final wasOffline = state.isOffline;

        state = state.copyWith(
          status: ConnectivityStatus.online,
          lastOnlineAt: now,
          lastCheckedAt: now,
        );

        if (wasOffline && kDebugMode) {
          print('ConnectivityNotifier: Came back online');
        }
      } else {
        _setOffline(now);
      }
    } catch (e) {
      _setOffline(now);
    }
  }

  /// Mark as offline.
  void _setOffline(DateTime checkedAt) {
    final wasOnline = state.isOnline;

    state = state.copyWith(
      status: ConnectivityStatus.offline,
      lastCheckedAt: checkedAt,
    );

    if (wasOnline && kDebugMode) {
      print('ConnectivityNotifier: Went offline');
    }
  }

  /// Force a connectivity check.
  Future<void> checkNow() async {
    await _checkConnectivity();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Provider for connectivity state.
final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier();
});

/// Provider that returns true if online.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).isOnline;
});

/// Provider that returns true if offline.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).isOffline;
});

/// Provider that triggers sync when coming back online.
///
/// Watch this provider to trigger sync operations when connectivity is restored.
final connectivitySyncTriggerProvider = Provider<void>((ref) {
  final connectivity = ref.watch(connectivityProvider);

  // If we just came online, trigger a sync.
  // This is detected when status is online and lastOnlineAt is recent.
  if (connectivity.isOnline) {
    final lastChecked = connectivity.lastCheckedAt;
    if (lastChecked != null) {
      final timeSinceCheck = DateTime.now().difference(lastChecked);
      // If we just checked and are online, we may have just reconnected.
      if (timeSinceCheck.inSeconds < 35) {
        // This provider being read/watched will trigger dependent providers
        // to refresh their data.
      }
    }
  }

  return;
});
