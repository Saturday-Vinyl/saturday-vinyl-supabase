import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/providers/playback_sync_provider.dart';

/// Observes app lifecycle changes and triggers foreground recovery.
class AppLifecycleObserver with WidgetsBindingObserver {
  AppLifecycleObserver(this._ref);

  final Ref _ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ref.read(playbackSyncProvider.notifier).onAppResumed();
    }
  }
}

/// Provider that registers an [AppLifecycleObserver] to catch
/// foreground resume events and re-sync playback state.
final appLifecycleProvider = Provider<AppLifecycleObserver>((ref) {
  final observer = AppLifecycleObserver(ref);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  return observer;
});
