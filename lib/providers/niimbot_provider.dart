import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/services/niimbot/niimbot_printer.dart';
import 'package:saturday_app/repositories/settings_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// State representing the Niimbot printer connection
class NiimbotState {
  final bool isConnected;
  final String? portPath;
  final String? lastError;

  const NiimbotState({
    this.isConnected = false,
    this.portPath,
    this.lastError,
  });

  NiimbotState copyWith({
    bool? isConnected,
    String? portPath,
    String? lastError,
    bool clearError = false,
    bool clearPort = false,
  }) {
    return NiimbotState(
      isConnected: isConnected ?? this.isConnected,
      portPath: clearPort ? null : (portPath ?? this.portPath),
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Notifier managing Niimbot printer connection and state
class NiimbotNotifier extends StateNotifier<NiimbotState> {
  final NiimbotPrinter _printer = NiimbotPrinter();
  final SettingsRepository _settingsRepository = SettingsRepository();

  NiimbotNotifier() : super(const NiimbotState());

  /// Get the underlying printer instance for direct printing
  NiimbotPrinter get printer => _printer;

  /// Check if printer is connected
  bool get isConnected => _printer.isConnected;

  /// Get available serial ports
  List<String> getAvailablePorts() {
    return NiimbotPrinter.getAvailablePorts();
  }

  /// Connect to the printer at the specified port
  Future<bool> connect(String portPath) async {
    try {
      AppLogger.info('NiimbotNotifier: Connecting to $portPath');

      final success = await _printer.connect(portPath);

      if (success) {
        state = NiimbotState(
          isConnected: true,
          portPath: portPath,
        );
        AppLogger.info('NiimbotNotifier: Connected successfully');
        return true;
      } else {
        state = state.copyWith(
          isConnected: false,
          lastError: 'Failed to connect to printer',
        );
        return false;
      }
    } catch (e) {
      AppLogger.error('NiimbotNotifier: Connection error', e);
      state = state.copyWith(
        isConnected: false,
        lastError: 'Connection error: $e',
      );
      return false;
    }
  }

  /// Connect using saved settings
  Future<bool> connectFromSettings() async {
    try {
      final settings = await _settingsRepository.loadPrinterSettings();
      final port = settings.niimbotPort;

      if (port == null || port.isEmpty) {
        state = state.copyWith(
          lastError: 'No Niimbot port configured in settings',
        );
        return false;
      }

      return await connect(port);
    } catch (e) {
      AppLogger.error('NiimbotNotifier: Error loading settings', e);
      state = state.copyWith(
        lastError: 'Failed to load settings: $e',
      );
      return false;
    }
  }

  /// Disconnect from the printer
  void disconnect() {
    _printer.disconnect();
    state = const NiimbotState(isConnected: false);
    AppLogger.info('NiimbotNotifier: Disconnected');
  }

  /// Get battery level
  Future<int?> getBatteryLevel() async {
    if (!isConnected) return null;
    return await _printer.getBatteryLevel();
  }

  /// Send heartbeat and check status
  Future<Map<String, int?>?> heartbeat() async {
    if (!isConnected) return null;
    return await _printer.heartbeat();
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  @override
  void dispose() {
    _printer.disconnect();
    super.dispose();
  }
}

/// Provider for Niimbot printer state management
final niimbotProvider =
    StateNotifierProvider<NiimbotNotifier, NiimbotState>((ref) {
  final notifier = NiimbotNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

/// Provider for direct access to the NiimbotPrinter instance
/// Use this for printing operations
final niimbotPrinterProvider = Provider<NiimbotPrinter>((ref) {
  return ref.watch(niimbotProvider.notifier).printer;
});

/// Provider for checking if the Niimbot printer is connected
final isNiimbotConnectedProvider = Provider<bool>((ref) {
  return ref.watch(niimbotProvider).isConnected;
});

/// Provider for available serial ports
final availableNiimbotPortsProvider = Provider<List<String>>((ref) {
  return NiimbotPrinter.getAvailablePorts();
});
