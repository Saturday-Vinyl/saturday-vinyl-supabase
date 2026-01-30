import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Response from a device command
class CommandResponse {
  final String id;
  final String status;
  final String? message;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  CommandResponse({
    required this.id,
    required this.status,
    this.message,
    this.data = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isSuccess => status == 'ok' || status == 'completed';
  bool get isError => status == 'error' || status == 'failed';
  bool get isAcknowledged => status == 'acknowledged';

  factory CommandResponse.fromJson(Map<String, dynamic> json) {
    return CommandResponse(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      message: json['message'] as String?,
      data: json['data'] != null
          ? Map<String, dynamic>.from(json['data'] as Map)
          : {},
    );
  }

  factory CommandResponse.timeout(String commandId) {
    return CommandResponse(
      id: commandId,
      status: 'error',
      message: 'Command timed out',
    );
  }

  factory CommandResponse.error(String commandId, String errorMessage) {
    return CommandResponse(
      id: commandId,
      status: 'error',
      message: errorMessage,
    );
  }
}

/// Parameters for factory provisioning
class FactoryProvisionParams {
  final String serialNumber;
  final String name;
  final String? cloudUrl;
  final String? cloudAnonKey;
  final String? wifiSsid;
  final String? wifiPassword;
  final String? threadNetworkName;
  final int? threadChannel;
  final int? threadPanId;
  final String? threadNetworkKey;
  final Map<String, dynamic> additionalParams;

  FactoryProvisionParams({
    required this.serialNumber,
    required this.name,
    this.cloudUrl,
    this.cloudAnonKey,
    this.wifiSsid,
    this.wifiPassword,
    this.threadNetworkName,
    this.threadChannel,
    this.threadPanId,
    this.threadNetworkKey,
    this.additionalParams = const {},
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'serial_number': serialNumber,
      'name': name,
      ...additionalParams,
    };

    if (cloudUrl != null) map['cloud_url'] = cloudUrl;
    if (cloudAnonKey != null) map['cloud_anon_key'] = cloudAnonKey;
    if (wifiSsid != null) map['wifi_ssid'] = wifiSsid;
    if (wifiPassword != null) map['wifi_password'] = wifiPassword;
    if (threadNetworkName != null) {
      map['thread_network_name'] = threadNetworkName;
    }
    if (threadChannel != null) map['thread_channel'] = threadChannel;
    if (threadPanId != null) map['thread_pan_id'] = threadPanId;
    if (threadNetworkKey != null) map['thread_network_key'] = threadNetworkKey;

    return map;
  }
}

/// Command timeouts for Device Command Protocol
class DeviceCommandTimeouts {
  static const Duration probe = Duration(seconds: 2);
  static const Duration standard = Duration(seconds: 10);
  static const Duration wifiTest = Duration(seconds: 45);
  static const Duration cloudTest = Duration(seconds: 15);
  static const Duration allTests = Duration(seconds: 90);
  static const Duration otaUpdate = Duration(minutes: 5);

  static Duration getTestTimeout(String capability, String testName) {
    if (capability == 'wifi' && testName == 'connect') {
      return wifiTest;
    }
    if (capability == 'cloud' && testName == 'connect') {
      return cloudTest;
    }
    return standard;
  }
}

/// Service for communicating with devices using the Device Command Protocol v1.2.3
///
/// This implements the always-listening architecture where devices accept commands
/// immediately without requiring an entry window. Commands use UUID tracking and
/// follow the flat parameter/response format defined in the protocol.
class DeviceCommunicationService {
  static const int _baudRate = 115200;
  static const _uuid = Uuid();

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _readerSubscription;

  final _responseController = StreamController<CommandResponse>.broadcast();
  final _rawLogController = StreamController<String>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  /// Stream of command responses from device
  Stream<CommandResponse> get responseStream => _responseController.stream;

  /// Stream of raw log lines (all serial output)
  Stream<String> get rawLogStream => _rawLogController.stream;

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  final StringBuffer _lineBuffer = StringBuffer();
  bool _isConnected = false;
  String? _currentPortName;

  bool get isConnected => _isConnected;
  String? get currentPortName => _currentPortName;

  /// Connect to device serial port
  Future<bool> connect(String portName) async {
    if (_isConnected) {
      await disconnect();
    }

    try {
      _port = SerialPort(portName);

      if (!_port!.openReadWrite()) {
        final error = SerialPort.lastError;
        AppLogger.error('Failed to open port $portName: $error');
        _rawLogController.add('[ERROR] Failed to open port: $error');
        try {
          _port?.dispose();
        } catch (_) {}
        _port = null;
        return false;
      }

      // Configure port: 115200 baud, 8N1, no flow control
      final config = SerialPortConfig()
        ..baudRate = _baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);

      try {
        _port!.config = config;
        _rawLogController.add('[INFO] Port configured: $_baudRate baud, 8N1');
      } catch (e) {
        AppLogger.error('Failed to configure port $portName', e);
        _rawLogController.add('[ERROR] Failed to configure port: $e');
        await disconnect();
        return false;
      }

      // Flush any stale data in the buffers
      try {
        _port!.flush();
        _rawLogController.add('[INFO] Buffers flushed');
      } catch (e) {
        _rawLogController.add('[WARN] Could not flush buffers: $e');
      }

      // Small delay to allow port to stabilize
      await Future.delayed(const Duration(milliseconds: 100));

      // Start reading
      try {
        _reader = SerialPortReader(_port!);
        _readerSubscription = _reader!.stream.listen(
          _handleData,
          onError: (error) {
            AppLogger.error('Serial read error', error);
            _rawLogController.add('[ERROR] Serial read error: $error');
          },
          onDone: () {
            _rawLogController.add('[INFO] Serial connection closed');
            _setConnected(false, null);
          },
        );
      } catch (e) {
        AppLogger.error('Failed to start reading from $portName', e);
        _rawLogController.add('[ERROR] Failed to start reading: $e');
        await disconnect();
        return false;
      }

      _setConnected(true, portName);
      _rawLogController.add('[INFO] Connected to $portName at $_baudRate baud');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to connect to $portName', e, stackTrace);
      _rawLogController.add('[ERROR] Failed to connect: $e');
      await disconnect();
      return false;
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    if (_port == null && _reader == null && _readerSubscription == null) {
      return;
    }

    try {
      await _readerSubscription?.cancel();
    } catch (e) {
      AppLogger.error('Error cancelling reader subscription', e);
    }
    _readerSubscription = null;

    try {
      _reader?.close();
    } catch (e) {
      AppLogger.error('Error closing serial reader', e);
    }
    _reader = null;

    if (_port != null) {
      try {
        if (_port!.isOpen) {
          _port!.close();
        }
      } catch (e) {
        AppLogger.error('Error closing serial port', e);
      }

      try {
        _port!.dispose();
      } catch (e) {
        AppLogger.error('Error disposing serial port', e);
      }
      _port = null;

      // Allow OS to release port handle
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _lineBuffer.clear();
    _setConnected(false, null);
    _rawLogController.add('[INFO] Disconnected');
  }

  void _setConnected(bool connected, String? portName) {
    _isConnected = connected;
    _currentPortName = portName;
    _connectionStateController.add(connected);
  }

  // ============================================
  // Core Command Protocol
  // ============================================

  /// Send a command and wait for response
  Future<CommandResponse> sendCommand(
    String cmd, {
    String? capability,
    String? testName,
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    final commandId = _uuid.v4();

    if (!_isConnected || _port == null) {
      _rawLogController.add('[ERROR] Not connected');
      return CommandResponse.error(commandId, 'Not connected');
    }

    // Build command JSON per Device Command Protocol
    final command = <String, dynamic>{
      'id': commandId,
      'cmd': cmd,
    };
    if (capability != null) command['capability'] = capability;
    if (testName != null) command['test_name'] = testName;
    if (params != null && params.isNotEmpty) command['params'] = params;

    final jsonString = '${jsonEncode(command)}\n';
    _rawLogController.add('[TX] ${jsonString.trim()}');

    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      final bytesWritten = _port!.write(bytes);
      _port!.drain(); // Wait for data to be transmitted

      if (bytesWritten != bytes.length) {
        _rawLogController.add('[WARN] Only wrote $bytesWritten of ${bytes.length} bytes');
      }

      // Wait for response with matching ID
      final completer = Completer<CommandResponse>();

      late StreamSubscription<CommandResponse> subscription;
      Timer? timeoutTimer;

      subscription = responseStream.listen((response) {
        // Match response by ID
        if (response.id == commandId) {
          timeoutTimer?.cancel();
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.complete(response);
          }
        }
      });

      final effectiveTimeout = timeout ?? DeviceCommandTimeouts.standard;
      timeoutTimer = Timer(effectiveTimeout, () {
        subscription.cancel();
        if (!completer.isCompleted) {
          _rawLogController.add('[TIMEOUT] No response for $cmd');
          completer.complete(CommandResponse.timeout(commandId));
        }
      });

      return await completer.future;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to send command', e, stackTrace);
      _rawLogController.add('[ERROR] Failed to send: $e');
      return CommandResponse.error(commandId, e.toString());
    }
  }

  // ============================================
  // Device Command Protocol Commands
  // ============================================

  /// Get device status (get_status command)
  Future<CommandResponse> getStatus() async {
    return sendCommand('get_status', timeout: DeviceCommandTimeouts.standard);
  }

  /// Get device capabilities (get_capabilities command)
  Future<CommandResponse> getCapabilities() async {
    return sendCommand(
      'get_capabilities',
      timeout: DeviceCommandTimeouts.standard,
    );
  }

  /// Factory provision a device
  Future<CommandResponse> factoryProvision(FactoryProvisionParams params) async {
    return sendCommand(
      'factory_provision',
      params: params.toJson(),
      timeout: DeviceCommandTimeouts.standard,
    );
  }

  /// Update provision data on an already provisioned device
  Future<CommandResponse> setProvisionData(Map<String, dynamic> data) async {
    return sendCommand(
      'set_provision_data',
      params: data,
      timeout: DeviceCommandTimeouts.standard,
    );
  }

  /// Get stored provision data from device
  Future<CommandResponse> getProvisionData() async {
    return sendCommand(
      'get_provision_data',
      timeout: DeviceCommandTimeouts.standard,
    );
  }

  /// Run a capability test
  Future<CommandResponse> runTest(
    String capability,
    String testName, {
    Map<String, dynamic>? params,
  }) async {
    final timeout = DeviceCommandTimeouts.getTestTimeout(capability, testName);
    return sendCommand(
      'run_test',
      capability: capability,
      testName: testName,
      params: params,
      timeout: timeout,
    );
  }

  /// Consumer reset (clear consumer data, preserve factory config)
  Future<CommandResponse> consumerReset() async {
    _rawLogController.add('[INFO] Executing consumer reset...');
    final response = await sendCommand(
      'consumer_reset',
      timeout: DeviceCommandTimeouts.standard,
    );
    if (response.isSuccess) {
      _rawLogController.add('[INFO] Consumer reset complete - device may reboot');
    }
    return response;
  }

  /// Factory reset (full reset including factory data)
  Future<CommandResponse> factoryReset() async {
    _rawLogController.add('[INFO] Executing factory reset...');
    final response = await sendCommand(
      'factory_reset',
      timeout: DeviceCommandTimeouts.standard,
    );
    if (response.isSuccess) {
      _rawLogController.add('[INFO] Factory reset complete - device will reboot');
    }
    return response;
  }

  /// Reboot device
  Future<CommandResponse> reboot() async {
    _rawLogController.add('[INFO] Rebooting device...');
    return sendCommand('reboot', timeout: DeviceCommandTimeouts.standard);
  }

  /// Trigger OTA update
  Future<CommandResponse> otaUpdate({
    required String firmwareId,
    required String targetVersion,
    required String firmwareUrl,
  }) async {
    _rawLogController.add('[INFO] Starting OTA update to v$targetVersion...');
    return sendCommand(
      'ota_update',
      params: {
        'firmware_id': firmwareId,
        'target_version': targetVersion,
        'firmware_url': firmwareUrl,
      },
      timeout: DeviceCommandTimeouts.otaUpdate,
    );
  }

  // ============================================
  // Quick Probe (for device identification)
  // ============================================

  /// Probe a port to identify if it's a Saturday device
  ///
  /// Opens the port, sends get_status, and returns device info if successful.
  /// This is used by USBMonitorService to identify connected devices.
  static Future<ConnectedDevice?> probePort(String portName) async {
    SerialPort? port;
    SerialPortReader? reader;
    StreamSubscription? subscription;

    AppLogger.info('Probe: Attempting to probe port $portName');

    try {
      port = SerialPort(portName);

      if (!port.openReadWrite()) {
        final error = SerialPort.lastError;
        AppLogger.info('Probe: Failed to open port $portName: $error');
        return null;
      }

      AppLogger.info('Probe: Port $portName opened successfully');

      // Configure port
      final config = SerialPortConfig()
        ..baudRate = _baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);

      try {
        port.config = config;
        AppLogger.info('Probe: Port $portName configured at $_baudRate baud');
      } catch (e) {
        AppLogger.info('Probe: Failed to configure port $portName: $e');
        return null;
      }

      await Future.delayed(const Duration(milliseconds: 100));

      // Set up reader
      reader = SerialPortReader(port);
      final lineBuffer = StringBuffer();
      final responseCompleter = Completer<Map<String, dynamic>?>();

      subscription = reader.stream.listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        AppLogger.info('Probe: Received ${data.length} bytes from $portName: ${text.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}');
        for (final char in text.runes) {
          if (char == 10 || char == 13) {
            final line = lineBuffer.toString().trim();
            lineBuffer.clear();

            if (line.isNotEmpty) {
              AppLogger.info('Probe: Complete line from $portName: $line');
            }

            if (line.startsWith('{')) {
              try {
                final json = jsonDecode(line) as Map<String, dynamic>;
                AppLogger.info('Probe: Parsed JSON from $portName: $json');
                // Check for get_status response
                if (json['status'] == 'ok' && json['data'] != null) {
                  AppLogger.info('Probe: Valid status response from $portName');
                  if (!responseCompleter.isCompleted) {
                    responseCompleter
                        .complete(json['data'] as Map<String, dynamic>);
                  }
                } else {
                  AppLogger.info('Probe: JSON missing status=ok or data field: status=${json['status']}, hasData=${json['data'] != null}');
                }
              } catch (e) {
                AppLogger.info('Probe: JSON parse failed for line: $e');
              }
            }
          } else {
            lineBuffer.writeCharCode(char);
          }
        }
      });

      // Send get_status probe
      final commandId = _uuid.v4();
      final command = jsonEncode({'id': commandId, 'cmd': 'get_status'});
      AppLogger.info('Probe: Sending to $portName: $command');
      port.write(Uint8List.fromList(utf8.encode('$command\n')));

      // Wait for response with timeout
      AppLogger.info('Probe: Waiting for response from $portName (timeout: ${DeviceCommandTimeouts.probe.inSeconds}s)');
      final responseData = await responseCompleter.future
          .timeout(DeviceCommandTimeouts.probe, onTimeout: () {
        AppLogger.info('Probe: Timeout waiting for response from $portName');
        return null;
      });

      if (responseData != null && responseData['device_type'] != null) {
        AppLogger.info('Probe: SUCCESS - Found Saturday device on $portName: ${responseData['device_type']}');
        return ConnectedDevice.fromStatusResponse(
          portName: portName,
          data: responseData,
        );
      }

      AppLogger.info('Probe: No valid Saturday device response from $portName (responseData: $responseData)');
      return null;
    } catch (e, stack) {
      AppLogger.info('Probe: Error on $portName: $e');
      AppLogger.debug('Probe stack trace', e, stack);
      return null;
    } finally {
      // Clean up
      try {
        await subscription?.cancel();
      } catch (_) {}
      try {
        reader?.close();
      } catch (_) {}
      try {
        if (port?.isOpen ?? false) {
          port!.close();
        }
      } catch (_) {}
      try {
        port?.dispose();
      } catch (_) {}
      // Allow OS to release port
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // ============================================
  // Data Handling
  // ============================================

  void _handleData(Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true);

    for (final char in text.runes) {
      if (char == 10 || char == 13) {
        final line = _lineBuffer.toString().trim();
        _lineBuffer.clear();

        if (line.isNotEmpty) {
          _processLine(line);
        }
      } else {
        _lineBuffer.writeCharCode(char);
      }
    }
  }

  void _processLine(String line) {
    _rawLogController.add('[RX] $line');

    // Only process JSON lines
    if (!line.startsWith('{')) {
      return;
    }

    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final response = CommandResponse.fromJson(json);
      _responseController.add(response);
    } catch (e) {
      AppLogger.debug('Failed to parse JSON response: $e');
    }
  }

  /// Dispose the service and release all resources
  void dispose() {
    _readerSubscription?.cancel();
    _readerSubscription = null;

    try {
      _reader?.close();
    } catch (_) {}
    _reader = null;

    if (_port != null) {
      try {
        if (_port!.isOpen) {
          _port!.close();
        }
      } catch (_) {}

      try {
        _port!.dispose();
      } catch (_) {}
      _port = null;
    }

    _lineBuffer.clear();
    _isConnected = false;
    _currentPortName = null;

    _responseController.close();
    _rawLogController.close();
    _connectionStateController.close();
  }
}
