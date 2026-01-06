import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saturday_consumer_app/providers/library_view_provider.dart';

/// Key for storing the last shown splash version.
const String _splashVersionKey = 'intro_splash_version_shown';

/// Provider for app package info.
///
/// Must be overridden in main.dart with the actual instance.
final packageInfoProvider = Provider<PackageInfo>((ref) {
  throw UnimplementedError(
    'packageInfoProvider must be overridden in main.dart',
  );
});

/// Provider that returns the current app version string.
final appVersionProvider = Provider<String>((ref) {
  final packageInfo = ref.watch(packageInfoProvider);
  return packageInfo.version;
});

/// Provider that determines if the intro splash should be shown.
///
/// Returns true if:
/// - No splash version has been stored (first launch)
/// - The stored version is different from the current version (app update)
final shouldShowIntroSplashProvider = Provider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final currentVersion = ref.watch(appVersionProvider);
  final lastShownVersion = prefs.getString(_splashVersionKey);

  // Show splash if no version stored or version has changed
  return lastShownVersion == null || lastShownVersion != currentVersion;
});

/// StateNotifier for managing intro splash state.
class IntroSplashNotifier extends StateNotifier<bool> {
  IntroSplashNotifier(this._prefs, this._currentVersion)
      : super(_shouldShowSplash(_prefs, _currentVersion));

  final SharedPreferences _prefs;
  final String _currentVersion;

  /// Determine initial state - whether to show splash.
  static bool _shouldShowSplash(SharedPreferences prefs, String currentVersion) {
    final lastShownVersion = prefs.getString(_splashVersionKey);
    return lastShownVersion == null || lastShownVersion != currentVersion;
  }

  /// Mark the splash as shown for the current version.
  Future<void> markSplashShown() async {
    await _prefs.setString(_splashVersionKey, _currentVersion);
    state = false;
  }

  /// Reset splash state (useful for testing).
  Future<void> resetSplash() async {
    await _prefs.remove(_splashVersionKey);
    state = true;
  }
}

/// Provider for intro splash notifier with persistence.
final introSplashNotifierProvider =
    StateNotifierProvider<IntroSplashNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final currentVersion = ref.watch(appVersionProvider);
  return IntroSplashNotifier(prefs, currentVersion);
});
