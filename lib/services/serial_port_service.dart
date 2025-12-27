import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for managing serial port connections to UHF RFID modules
///
/// This service handles:
/// - Serial port discovery and connection
/// - RTS pin control for module enable (EN pin)
/// - Data streaming and writing
/// - Connection state management
class SerialPortService {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSubscription;

  SerialConnectionState _state = SerialConnectionState.initial;
  bool _isModuleEnabled = false;

  final _stateController = StreamController<SerialConnectionState>.broadcast();
  final _dataController = StreamController<List<int>>.broadcast();

  /// Stream of connection state changes
  Stream<SerialConnectionState> get stateStream => _stateController.stream;

  /// Stream of incoming data (raw bytes)
  Stream<List<int>> get dataStream => _dataController.stream;

  /// Current connection state
  SerialConnectionState get state => _state;

  /// Check if connected
  bool get isConnected => _state.isConnected;

  /// Check if module is enabled (RTS deasserted = HIGH)
  bool get isModuleEnabled => _isModuleEnabled;

  /// Get list of available serial ports
  ///
  /// Returns port names that can be used with [connect]
  List<String> getAvailablePorts() {
    try {
      final ports = SerialPort.availablePorts;
      AppLogger.info('Found ${ports.length} serial ports: ${ports.join(", ")}');
      return ports;
    } catch (error, stackTrace) {
      AppLogger.error('Error listing serial ports', error, stackTrace);
      return [];
    }
  }

  /// Get detailed information about a specific port
  ///
  /// Returns a map with port details like description, manufacturer, etc.
  Map<String, String> getPortInfo(String portName) {
    try {
      final port = SerialPort(portName);
      final info = {
        'Port': portName,
        'Description': port.description ?? 'Unknown',
        'Manufacturer': port.manufacturer ?? 'Unknown',
        'Serial Number': port.serialNumber ?? 'Unknown',
        'Product ID': port.productId?.toString() ?? 'Unknown',
        'Vendor ID': port.vendorId?.toString() ?? 'Unknown',
      };
      port.dispose();
      return info;
    } catch (error) {
      AppLogger.error('Error getting port info for $portName', error, null);
      return {'Port': portName, 'Error': error.toString()};
    }
  }

  /// Connect to a serial port
  ///
  /// [portName] - Serial port name (e.g., '/dev/tty.usbserial-0001', 'COM3')
  /// [baudRate] - Baud rate (default: 115200)
  ///
  /// This method:
  /// 1. Opens the serial port
  /// 2. Configures it (8N1, no flow control)
  /// 3. Configures RTS to enable the RFID module (EN pin HIGH)
  /// 4. Waits for module initialization
  /// 5. Starts listening for incoming data
  Future<bool> connect(String portName, {int? baudRate}) async {
    final effectiveBaudRate = baudRate ?? RfidConfig.defaultBaudRate;

    if (_state.isConnected) {
      AppLogger.warning('Already connected to ${_state.portName}');
      return false;
    }

    _updateState(_state.copyWith(
      status: SerialConnectionStatus.connecting,
      portName: portName,
      baudRate: effectiveBaudRate,
      clearError: true,
    ));

    try {
      AppLogger.info('Connecting to RFID module on $portName at $effectiveBaudRate baud');

      _port = SerialPort(portName);

      // Open the port first
      if (!_port!.openReadWrite()) {
        final error = SerialPort.lastError;
        throw Exception('Failed to open port: ${error?.message ?? "Unknown error"}');
      }

      // Small delay to allow OS to stabilize the port
      await Future.delayed(const Duration(milliseconds: 50));

      // Configure serial port: 8 data bits, no parity, 1 stop bit, no flow control
      final config = SerialPortConfig()
        ..baudRate = effectiveBaudRate
        ..bits = RfidConfig.dataBits
        ..stopBits = RfidConfig.stopBits
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      _port!.config = config;

      // Configure RTS to enable the RFID module
      // Note: EN pin is ACTIVE-HIGH (>1.5V to enable)
      // RTS OFF (deasserted) = RTS pin HIGH = EN HIGH = module ON
      _setRts(true);
      _isModuleEnabled = true;

      // Wait for module to initialize
      AppLogger.info('Waiting ${RfidConfig.moduleEnableDelayMs}ms for module initialization');
      await Future.delayed(const Duration(milliseconds: RfidConfig.moduleEnableDelayMs));

      // Set up reader for incoming data
      _reader = SerialPortReader(_port!);
      _readerSubscription = _reader!.stream.listen(
        _handleIncomingData,
        onError: (error) {
          AppLogger.error('Serial port read error', error, null);
          _updateState(_state.copyWith(
            status: SerialConnectionStatus.error,
            errorMessage: 'Read error: $error',
          ));
        },
        onDone: () {
          AppLogger.info('Serial port reader closed');
          disconnect();
        },
      );

      // Wait a bit and log any initial garbage data that might be in the buffer
      await Future.delayed(const Duration(milliseconds: 100));
      AppLogger.info('Serial port ready for communication');

      _updateState(_state.copyWith(
        status: SerialConnectionStatus.connected,
        isModuleEnabled: true,
      ));

      AppLogger.info('Successfully connected to RFID module on $portName');
      return true;
    } catch (error, stackTrace) {
      AppLogger.error('Error connecting to RFID module', error, stackTrace);
      _updateState(_state.copyWith(
        status: SerialConnectionStatus.error,
        errorMessage: error.toString(),
      ));
      await disconnect();
      return false;
    }
  }

  /// Disconnect from the serial port
  ///
  /// This method:
  /// 1. Configures RTS to disable the RFID module
  /// 2. Closes the serial port
  /// 3. Cleans up resources
  Future<void> disconnect() async {
    AppLogger.info('Disconnecting from RFID module');

    try {
      // Set RTS to disable module before closing
      if (_port != null && _isModuleEnabled) {
        _setRts(false);
        _isModuleEnabled = false;
        // Brief delay to allow module to power down cleanly
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await _readerSubscription?.cancel();
      _readerSubscription = null;

      _reader?.close();
      _reader = null;

      _port?.close();
      _port?.dispose();
      _port = null;

      _updateState(SerialConnectionState.initial);

      AppLogger.info('Disconnected from RFID module');
    } catch (error, stackTrace) {
      AppLogger.error('Error during disconnect', error, stackTrace);
    }
  }

  /// Write data to the serial port
  ///
  /// Returns true if all bytes were written successfully
  Future<bool> write(List<int> data) async {
    if (!isConnected || _port == null) {
      AppLogger.warning('Cannot write: not connected');
      return false;
    }

    try {
      final bytes = Uint8List.fromList(data);
      final written = _port!.write(bytes);

      if (written == bytes.length) {
        AppLogger.debug('Wrote ${bytes.length} bytes: ${_formatHex(data)}');
        return true;
      } else {
        AppLogger.warning('Incomplete write: sent $written/${bytes.length} bytes');
        return false;
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error writing to serial port', error, stackTrace);
      return false;
    }
  }

  /// Enable or disable the RFID module via RTS pin
  ///
  /// [enabled] - true to enable module (RTS HIGH, EN pin HIGH)
  ///           - false to disable module (RTS LOW, EN pin LOW)
  void setModuleEnabled(bool enabled) {
    if (_port == null) {
      AppLogger.warning('Cannot set module enabled: not connected');
      return;
    }

    _setRts(enabled);
    _isModuleEnabled = enabled;
    _updateState(_state.copyWith(isModuleEnabled: enabled));
    AppLogger.info('RFID module ${enabled ? "enabled" : "disabled"} via RTS');
  }

  /// Set RTS pin state to control module enable
  ///
  /// The YRM1002 UHF module uses ACTIVE-HIGH enable logic:
  /// - EN > 1.5V → Module ON (enabled)
  /// - EN < 1.5V → Module OFF (disabled/power down)
  ///
  /// RTS behavior on CP2102N (3.3V logic):
  /// - RTS OFF (deasserted) → Pin goes HIGH (3.3V)
  /// - RTS ON  (asserted)   → Pin goes LOW  (0V)
  ///
  /// So to enable the module, we set RTS OFF (which pulls EN HIGH)
  void _setRts(bool enableModule) {
    if (_port == null) return;

    try {
      // Active-high logic: RTS OFF = EN HIGH = Module enabled
      if (enableModule) {
        _port!.config.rts = SerialPortRts.off;  // RTS OFF → EN HIGH → Module ON
      } else {
        _port!.config.rts = SerialPortRts.on;   // RTS ON → EN LOW → Module OFF
      }
      AppLogger.debug('RTS ${enableModule ? "OFF (EN=HIGH, module enabled)" : "ON (EN=LOW, module disabled)"}');
    } catch (error, stackTrace) {
      AppLogger.error('Error setting RTS', error, stackTrace);
    }
  }

  /// Handle incoming data from serial port
  void _handleIncomingData(Uint8List data) {
    try {
      _dataController.add(data.toList());
      AppLogger.debug('Received ${data.length} bytes: ${_formatHex(data.toList())}');
    } catch (error, stackTrace) {
      AppLogger.error('Error processing incoming data', error, stackTrace);
    }
  }

  /// Update connection state and notify listeners
  void _updateState(SerialConnectionState newState) {
    _state = newState;
    _stateController.add(_state);
    AppLogger.debug('Serial connection state: $_state');
  }

  /// Format bytes as hex string for logging
  String _formatHex(List<int> bytes) {
    if (bytes.length > 32) {
      return '${bytes.take(32).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}... (${bytes.length} bytes total)';
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _stateController.close();
    _dataController.close();
  }

  /// Static method to list available ports (for use without instance)
  static List<String> listAvailablePorts() {
    try {
      return SerialPort.availablePorts;
    } catch (error) {
      AppLogger.error('Error listing serial ports', error, null);
      return [];
    }
  }
}
