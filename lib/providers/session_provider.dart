import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Session monitor state
class SessionState {
  final DateTime? expiresAt;
  final Duration? timeRemaining;
  final bool needsRefresh;
  final bool isExpired;

  const SessionState({
    this.expiresAt,
    this.timeRemaining,
    this.needsRefresh = false,
    this.isExpired = false,
  });

  SessionState copyWith({
    DateTime? expiresAt,
    Duration? timeRemaining,
    bool? needsRefresh,
    bool? isExpired,
  }) {
    return SessionState(
      expiresAt: expiresAt ?? this.expiresAt,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      needsRefresh: needsRefresh ?? this.needsRefresh,
      isExpired: isExpired ?? this.isExpired,
    );
  }
}

/// Session monitor notifier
class SessionMonitorNotifier extends StateNotifier<SessionState> {
  SessionMonitorNotifier(this.ref) : super(const SessionState()) {
    _startMonitoring();
  }

  final Ref ref;
  Timer? _timer;

  void _startMonitoring() {
    // Check session every minute
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkSession();
    });

    // Initial check
    _checkSession();
  }

  void _checkSession() {
    final authService = ref.read(authServiceProvider);

    if (!authService.isSignedIn) {
      state = const SessionState(isExpired: true);
      return;
    }

    final expiry = authService.getSessionExpiry();
    final timeRemaining = authService.getTimeUntilExpiry();

    if (timeRemaining == null || timeRemaining.isNegative) {
      state = const SessionState(isExpired: true);
      AppLogger.warning('Session has expired');
      return;
    }

    final needsRefresh = authService.shouldRefreshSession();

    state = SessionState(
      expiresAt: expiry,
      timeRemaining: timeRemaining,
      needsRefresh: needsRefresh,
      isExpired: false,
    );

    // Auto-refresh if needed
    if (needsRefresh && !state.isExpired) {
      _autoRefreshSession();
    }
  }

  Future<void> _autoRefreshSession() async {
    AppLogger.info('Auto-refreshing session (${state.timeRemaining?.inMinutes} minutes remaining)');

    final authService = ref.read(authServiceProvider);
    final success = await authService.refreshSession();

    if (success) {
      _checkSession(); // Re-check after refresh
    } else {
      AppLogger.error('Auto-refresh failed');
    }
  }

  Future<void> manualRefresh() async {
    final authService = ref.read(authServiceProvider);
    await authService.refreshSession();
    _checkSession();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Session monitor provider
final sessionMonitorProvider =
    StateNotifierProvider<SessionMonitorNotifier, SessionState>((ref) {
  return SessionMonitorNotifier(ref);
});

/// Provider to check if session is expiring soon (less than 30 minutes)
final isSessionExpiringSoonProvider = Provider<bool>((ref) {
  final sessionState = ref.watch(sessionMonitorProvider);

  if (sessionState.isExpired) return false;
  if (sessionState.timeRemaining == null) return false;

  return sessionState.timeRemaining!.inMinutes < 30;
});

/// Provider to get friendly time remaining text
final sessionTimeRemainingTextProvider = Provider<String?>((ref) {
  final sessionState = ref.watch(sessionMonitorProvider);

  if (sessionState.isExpired) return 'Expired';
  if (sessionState.timeRemaining == null) return null;

  final duration = sessionState.timeRemaining!;

  if (duration.inDays > 0) {
    return '${duration.inDays} ${duration.inDays == 1 ? 'day' : 'days'}';
  } else if (duration.inHours > 0) {
    return '${duration.inHours} ${duration.inHours == 1 ? 'hour' : 'hours'}';
  } else if (duration.inMinutes > 0) {
    return '${duration.inMinutes} ${duration.inMinutes == 1 ? 'minute' : 'minutes'}';
  } else {
    return 'Less than a minute';
  }
});
