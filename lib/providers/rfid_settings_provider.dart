import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/rfid_settings.dart';
import 'package:saturday_app/services/rfid_settings_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  );
});

/// Provider for RfidSettingsService singleton
final rfidSettingsServiceProvider = Provider<RfidSettingsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return RfidSettingsService(prefs);
});

/// State for RFID settings with loading status
class RfidSettingsState {
  final RfidSettings settings;
  final bool isLoading;
  final String? error;

  const RfidSettingsState({
    required this.settings,
    this.isLoading = false,
    this.error,
  });

  factory RfidSettingsState.initial() {
    return RfidSettingsState(
      settings: RfidSettings.defaults(),
      isLoading: true,
    );
  }

  RfidSettingsState copyWith({
    RfidSettings? settings,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return RfidSettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// AsyncNotifier for managing RFID settings state
class RfidSettingsNotifier extends StateNotifier<RfidSettingsState> {
  final RfidSettingsService _service;

  RfidSettingsNotifier(this._service) : super(RfidSettingsState.initial()) {
    _loadSettings();
  }

  /// Load all settings from storage
  Future<void> _loadSettings() async {
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      final settings = await _service.loadAllSettings();
      state = state.copyWith(settings: settings, isLoading: false);
      AppLogger.debug('RfidSettingsNotifier: Loaded settings: $settings');
    } catch (e) {
      AppLogger.error('RfidSettingsNotifier: Failed to load settings', e);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load settings: $e',
      );
    }
  }

  /// Reload settings from storage
  Future<void> reload() async {
    await _loadSettings();
  }

  /// Update the serial port
  Future<void> updatePort(String? port) async {
    try {
      if (port != null && port.isNotEmpty) {
        await _service.savePort(port);
      } else {
        await _service.clearPort();
      }
      state = state.copyWith(
        settings: state.settings.copyWith(
          port: port,
          clearPort: port == null || port.isEmpty,
        ),
        clearError: true,
      );
      AppLogger.debug('RfidSettingsNotifier: Updated port to: $port');
    } catch (e) {
      AppLogger.error('RfidSettingsNotifier: Failed to update port', e);
      state = state.copyWith(error: 'Failed to save port: $e');
    }
  }

  /// Update the baud rate
  Future<void> updateBaudRate(int baudRate) async {
    try {
      await _service.saveBaudRate(baudRate);
      state = state.copyWith(
        settings: state.settings.copyWith(baudRate: baudRate),
        clearError: true,
      );
      AppLogger.debug('RfidSettingsNotifier: Updated baud rate to: $baudRate');
    } catch (e) {
      AppLogger.error('RfidSettingsNotifier: Failed to update baud rate', e);
      state = state.copyWith(error: 'Failed to save baud rate: $e');
    }
  }

  /// Update the RF power level
  Future<void> updateRfPower(int dbm) async {
    try {
      await _service.saveRfPower(dbm);
      // Get the actual saved value (may be clamped)
      final savedPower = _service.getRfPower();
      state = state.copyWith(
        settings: state.settings.copyWith(rfPower: savedPower),
        clearError: true,
      );
      AppLogger.debug('RfidSettingsNotifier: Updated RF power to: $savedPower');
    } catch (e) {
      AppLogger.error('RfidSettingsNotifier: Failed to update RF power', e);
      state = state.copyWith(error: 'Failed to save RF power: $e');
    }
  }

  /// Update the access password
  ///
  /// [passwordHex] must be 8 hex characters or null/empty to clear
  Future<void> updateAccessPassword(String? passwordHex) async {
    try {
      if (passwordHex != null && passwordHex.isNotEmpty) {
        await _service.saveAccessPassword(passwordHex);
        state = state.copyWith(
          settings: state.settings.copyWith(accessPassword: passwordHex),
          clearError: true,
        );
      } else {
        await _service.clearAccessPassword();
        state = state.copyWith(
          settings: state.settings.copyWith(clearAccessPassword: true),
          clearError: true,
        );
      }
      AppLogger.debug('RfidSettingsNotifier: Updated access password');
    } catch (e) {
      AppLogger.error('RfidSettingsNotifier: Failed to update access password', e);
      state = state.copyWith(error: 'Failed to save access password: $e');
    }
  }

  /// Clear all settings
  Future<void> clearAllSettings() async {
    try {
      await _service.clearSettings();
      state = state.copyWith(
        settings: RfidSettings.defaults(),
        clearError: true,
      );
      AppLogger.info('RfidSettingsNotifier: Cleared all settings');
    } catch (e) {
      AppLogger.error('RfidSettingsNotifier: Failed to clear settings', e);
      state = state.copyWith(error: 'Failed to clear settings: $e');
    }
  }
}

/// Provider for RFID settings state
final rfidSettingsProvider =
    StateNotifierProvider<RfidSettingsNotifier, RfidSettingsState>((ref) {
  final service = ref.watch(rfidSettingsServiceProvider);
  return RfidSettingsNotifier(service);
});

/// Convenience provider for just the settings (without loading state)
final currentRfidSettingsProvider = Provider<RfidSettings>((ref) {
  return ref.watch(rfidSettingsProvider).settings;
});

/// Provider for checking if settings have been loaded
final rfidSettingsLoadedProvider = Provider<bool>((ref) {
  return !ref.watch(rfidSettingsProvider).isLoading;
});

/// Provider for settings error state
final rfidSettingsErrorProvider = Provider<String?>((ref) {
  return ref.watch(rfidSettingsProvider).error;
});
