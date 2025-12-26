import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/models/tag_poll_result.dart';
import 'package:saturday_app/providers/rfid_settings_provider.dart';
import 'package:saturday_app/services/serial_port_service.dart';
import 'package:saturday_app/services/uhf_rfid_service.dart';

/// Provider for the serial port service (singleton)
final serialPortServiceProvider = Provider<SerialPortService>((ref) {
  final service = SerialPortService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the UHF RFID service (singleton)
final uhfRfidServiceProvider = Provider<UhfRfidService>((ref) {
  final serialPortService = ref.watch(serialPortServiceProvider);
  final service = UhfRfidService(serialPortService);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for connection state changes
final uhfConnectionStateProvider = StreamProvider<SerialConnectionState>((ref) {
  final service = ref.watch(uhfRfidServiceProvider);
  return service.connectionStateStream;
});

/// Provider for current connection state (synchronous access)
final uhfCurrentConnectionStateProvider = Provider<SerialConnectionState>((ref) {
  final service = ref.watch(uhfRfidServiceProvider);
  return service.connectionState;
});

/// Provider for checking if connected
final uhfIsConnectedProvider = Provider<bool>((ref) {
  final service = ref.watch(uhfRfidServiceProvider);
  return service.isConnected;
});

/// Stream provider for tag poll results
final uhfPollStreamProvider = StreamProvider<TagPollResult>((ref) {
  final service = ref.watch(uhfRfidServiceProvider);
  return service.pollStream;
});

/// State for polling control
class UhfPollingState {
  final bool isPolling;
  final Set<String> foundEpcs;
  final String? lastError;

  const UhfPollingState({
    this.isPolling = false,
    this.foundEpcs = const {},
    this.lastError,
  });

  UhfPollingState copyWith({
    bool? isPolling,
    Set<String>? foundEpcs,
    String? lastError,
    bool clearError = false,
  }) {
    return UhfPollingState(
      isPolling: isPolling ?? this.isPolling,
      foundEpcs: foundEpcs ?? this.foundEpcs,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Notifier for polling control
class UhfPollingNotifier extends StateNotifier<UhfPollingState> {
  final UhfRfidService _service;
  StreamSubscription<TagPollResult>? _pollSubscription;

  UhfPollingNotifier(this._service) : super(const UhfPollingState());

  /// Start continuous polling
  Future<bool> startPolling() async {
    if (state.isPolling) return true;

    final success = await _service.startPolling();
    if (success) {
      // Subscribe to poll results
      _pollSubscription = _service.pollStream.listen((result) {
        state = state.copyWith(
          foundEpcs: {...state.foundEpcs, result.epcHex},
        );
      });

      state = state.copyWith(isPolling: true, clearError: true);
    } else {
      state = state.copyWith(lastError: 'Failed to start polling');
    }
    return success;
  }

  /// Stop continuous polling
  Future<void> stopPolling() async {
    await _pollSubscription?.cancel();
    _pollSubscription = null;

    await _service.stopPolling();
    state = state.copyWith(isPolling: false);
  }

  /// Clear found EPCs
  void clearFoundEpcs() {
    state = state.copyWith(foundEpcs: {});
  }

  /// Reset state
  void reset() {
    _pollSubscription?.cancel();
    _pollSubscription = null;
    state = const UhfPollingState();
  }

  @override
  void dispose() {
    _pollSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for polling control
final uhfPollingProvider =
    StateNotifierProvider<UhfPollingNotifier, UhfPollingState>((ref) {
  final service = ref.watch(uhfRfidServiceProvider);
  final notifier = UhfPollingNotifier(service);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

/// Provider for available serial ports
final availablePortsProvider = Provider<List<String>>((ref) {
  final service = ref.watch(serialPortServiceProvider);
  return service.getAvailablePorts();
});

/// Provider to refresh available ports (call .refresh() to update)
final refreshablePortsProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(serialPortServiceProvider);
  // Add a small delay to ensure USB devices are enumerated
  await Future.delayed(const Duration(milliseconds: 100));
  return service.getAvailablePorts();
});

/// Result of a test connection attempt
class TestConnectionResult {
  final bool success;
  final String message;
  final int? rfPower;

  const TestConnectionResult({
    required this.success,
    required this.message,
    this.rfPower,
  });

  factory TestConnectionResult.success({required int rfPower}) {
    return TestConnectionResult(
      success: true,
      message: 'Connection successful! Module RF power: $rfPower dBm',
      rfPower: rfPower,
    );
  }

  factory TestConnectionResult.failed(String message) {
    return TestConnectionResult(
      success: false,
      message: message,
    );
  }
}

/// Provider for testing connection to an RFID module
final testConnectionProvider =
    FutureProvider.family<TestConnectionResult, ({String port, int baudRate})>(
        (ref, params) async {
  final uhfService = ref.watch(uhfRfidServiceProvider);

  try {
    // Disconnect first if already connected
    if (uhfService.isConnected) {
      await uhfService.disconnect();
    }

    // Attempt to connect
    final connected = await uhfService.connect(
      params.port,
      baudRate: params.baudRate,
    );

    if (!connected) {
      return TestConnectionResult.failed(
          'Failed to connect to port ${params.port}');
    }

    // Try to get RF power as a simple test
    final power = await uhfService.getRfPower();

    if (power != null) {
      return TestConnectionResult.success(rfPower: power);
    } else {
      return TestConnectionResult.failed(
        'Connected but module did not respond. Check baud rate and module power.',
      );
    }
  } catch (e) {
    return TestConnectionResult.failed('Error: $e');
  }
});

/// Provider for connection with saved settings
final connectWithSettingsProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final uhfService = ref.watch(uhfRfidServiceProvider);
  final settingsState = ref.watch(rfidSettingsProvider);
  final settings = settingsState.settings;

  if (!settings.hasPort) {
    return false;
  }

  try {
    // Disconnect first if already connected
    if (uhfService.isConnected) {
      await uhfService.disconnect();
    }

    // Connect with saved settings
    final connected = await uhfService.connect(
      settings.port!,
      baudRate: settings.baudRate,
    );

    if (connected) {
      // Apply RF power
      await uhfService.setRfPower(settings.rfPower);

      // Set access password if provided
      if (settings.accessPasswordBytes != null) {
        uhfService.setAccessPassword(settings.accessPasswordBytes!);
      }
    }

    return connected;
  } catch (e) {
    return false;
  }
});
