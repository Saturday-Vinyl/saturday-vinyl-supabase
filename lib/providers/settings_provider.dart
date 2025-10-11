import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/printer_settings.dart';
import '../repositories/settings_repository.dart';
import '../utils/app_logger.dart';

/// Provider for settings repository
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// Provider for printer settings
final printerSettingsProvider =
    StateNotifierProvider<PrinterSettingsNotifier, AsyncValue<PrinterSettings>>(
        (ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  return PrinterSettingsNotifier(repository);
});

/// Notifier for managing printer settings state
class PrinterSettingsNotifier
    extends StateNotifier<AsyncValue<PrinterSettings>> {
  final SettingsRepository _repository;

  PrinterSettingsNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    _loadSettings();
  }

  /// Load settings from storage
  Future<void> _loadSettings() async {
    try {
      state = const AsyncValue.loading();
      final settings = await _repository.loadPrinterSettings();
      state = AsyncValue.data(settings);
    } catch (e, stackTrace) {
      AppLogger.error('Error loading printer settings', e);
      state = AsyncValue.error(e, stackTrace);
      // Fallback to default settings on error
      state = const AsyncValue.data(PrinterSettings.defaultSettings());
    }
  }

  /// Update printer settings and save to storage
  Future<void> updateSettings(PrinterSettings newSettings) async {
    try {
      AppLogger.info('Updating printer settings');

      // Validate settings before saving
      if (!newSettings.isValid()) {
        throw ArgumentError('Invalid printer settings');
      }

      // Optimistically update state
      state = AsyncValue.data(newSettings);

      // Save to storage
      await _repository.savePrinterSettings(newSettings);

      AppLogger.info('Printer settings updated successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Error updating printer settings', e);
      state = AsyncValue.error(e, stackTrace);
      // Reload settings from storage on error
      _loadSettings();
      rethrow;
    }
  }

  /// Update default printer
  Future<void> updateDefaultPrinter(
      String? printerId, String? printerName) async {
    final currentSettings = state.value;
    if (currentSettings == null) return;

    final updatedSettings = currentSettings.copyWith(
      defaultPrinterId: printerId,
      defaultPrinterName: printerName,
    );

    await updateSettings(updatedSettings);
  }

  /// Toggle auto-print setting
  Future<void> toggleAutoPrint() async {
    final currentSettings = state.value;
    if (currentSettings == null) return;

    final updatedSettings = currentSettings.copyWith(
      autoPrint: !currentSettings.autoPrint,
    );

    await updateSettings(updatedSettings);
  }

  /// Update label size
  Future<void> updateLabelSize(double width, double height) async {
    final currentSettings = state.value;
    if (currentSettings == null) return;

    final updatedSettings = currentSettings.copyWith(
      labelWidth: width,
      labelHeight: height,
    );

    await updateSettings(updatedSettings);
  }

  /// Reset settings to defaults
  Future<void> resetToDefaults() async {
    try {
      await _repository.clearPrinterSettings();
      state = const AsyncValue.data(PrinterSettings.defaultSettings());
      AppLogger.info('Printer settings reset to defaults');
    } catch (e, stackTrace) {
      AppLogger.error('Error resetting printer settings', e);
      state = AsyncValue.error(e, stackTrace);
      rethrow;
    }
  }

  /// Reload settings from storage
  Future<void> reload() async {
    await _loadSettings();
  }
}
