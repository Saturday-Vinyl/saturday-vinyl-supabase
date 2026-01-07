import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:saturday_app/models/service_mode_command.dart';
import 'package:saturday_app/models/service_mode_manifest.dart';
import 'package:saturday_app/models/service_mode_state.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for serial communication with devices using the Service Mode Protocol
class ServiceModeService {
  static const int _baudRate = 115200;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _readerSubscription;

  final _messageController = StreamController<ServiceModeMessage>.broadcast();
  final _rawLogController = StreamController<String>.broadcast();
  final _beaconController = StreamController<DeviceInfo>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  /// Stream of parsed JSON messages from device
  Stream<ServiceModeMessage> get messageStream => _messageController.stream;

  /// Stream of raw log lines (all serial output)
  Stream<String> get rawLogStream => _rawLogController.stream;

  /// Stream of device info from beacons
  Stream<DeviceInfo> get beaconStream => _beaconController.stream;

  /// Stream of connection state changes
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  final StringBuffer _lineBuffer = StringBuffer();
  bool _isConnected = false;
  DeviceInfo? _lastBeaconInfo;

  bool get isConnected => _isConnected;
  DeviceInfo? get lastBeaconInfo => _lastBeaconInfo;

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
        return false;
      }

      // Configure port: 115200 baud, 8N1, no flow control
      final config = SerialPortConfig()
        ..baudRate = _baudRate
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..setFlowControl(SerialPortFlowControl.none);
      _port!.config = config;

      // Start reading
      _reader = SerialPortReader(_port!);
      _readerSubscription = _reader!.stream.listen(
        _handleData,
        onError: (error) {
          AppLogger.error('Serial read error', error);
          _rawLogController.add('[ERROR] Serial read error: $error');
        },
        onDone: () {
          _rawLogController.add('[INFO] Serial connection closed');
          _setConnected(false);
        },
      );

      _setConnected(true);
      _rawLogController.add('[INFO] Connected to $portName at $_baudRate baud');
      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to connect to $portName', e, stackTrace);
      _rawLogController.add('[ERROR] Failed to connect: $e');
      return false;
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    await _readerSubscription?.cancel();
    _readerSubscription = null;
    _reader = null;

    if (_port != null && _port!.isOpen) {
      _port!.close();
    }
    _port?.dispose();
    _port = null;

    _lineBuffer.clear();
    _lastBeaconInfo = null;
    _setConnected(false);
    _rawLogController.add('[INFO] Disconnected');
  }

  void _setConnected(bool connected) {
    _isConnected = connected;
    _connectionStateController.add(connected);
  }

  /// Send a command and wait for response
  Future<ServiceModeMessage?> sendCommand(
    ServiceModeCommand command, {
    Duration? timeout,
  }) async {
    if (!_isConnected || _port == null) {
      _rawLogController.add('[ERROR] Not connected');
      return null;
    }

    final jsonString = command.toJsonString();
    _rawLogController.add('[TX] ${jsonString.trim()}');

    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      _port!.write(bytes);

      // Wait for response (non-beacon message)
      final completer = Completer<ServiceModeMessage?>();

      late StreamSubscription<ServiceModeMessage> subscription;
      Timer? timeoutTimer;

      subscription = messageStream.listen((message) {
        // Ignore beacon messages, wait for actual response
        if (!message.isBeacon) {
          timeoutTimer?.cancel();
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.complete(message);
          }
        }
      });

      final effectiveTimeout =
          timeout ?? ServiceModeTimeouts.standardCommand;
      timeoutTimer = Timer(effectiveTimeout, () {
        subscription.cancel();
        if (!completer.isCompleted) {
          _rawLogController.add('[TIMEOUT] No response for ${command.cmd}');
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to send command', e, stackTrace);
      _rawLogController.add('[ERROR] Failed to send: $e');
      return null;
    }
  }

  // ============================================
  // Service Mode Lifecycle
  // ============================================

  /// Enter service mode on a provisioned device
  ///
  /// Sends enter_service_mode repeatedly every 200ms for the full 10-second
  /// boot window. The device only listens for this command during the first
  /// 10 seconds after boot, so we spam aggressively to ensure we catch it.
  /// Returns true if service mode was entered successfully.
  Future<bool> enterServiceMode({
    Duration windowDuration = ServiceModeTimeouts.entryWindow,
    Duration interval = ServiceModeTimeouts.entryRetryInterval,
  }) async {
    if (!_isConnected) {
      _rawLogController.add('[ERROR] Not connected');
      return false;
    }

    _rawLogController.add('[INFO] Attempting to enter service mode...');
    _rawLogController.add('[INFO] Sending enter_service_mode every ${interval.inMilliseconds}ms for ${windowDuration.inSeconds}s');
    _rawLogController.add('[INFO] Reboot the device now to enter service mode');

    final deadline = DateTime.now().add(windowDuration);
    var attempt = 0;

    // Set up listener for success response
    final completer = Completer<bool>();
    late StreamSubscription<ServiceModeMessage> subscription;

    subscription = messageStream.listen((message) {
      if (message.isSuccess && !message.isBeacon) {
        // Got a success response - we're in service mode
        subscription.cancel();
        if (!completer.isCompleted) {
          _rawLogController.add('[INFO] Entered service mode');
          completer.complete(true);
        }
      } else if (message.errorCode == ServiceModeErrorCodes.windowExpired) {
        // Window expired explicitly
        subscription.cancel();
        if (!completer.isCompleted) {
          _rawLogController.add('[ERROR] Service mode entry window expired');
          completer.complete(false);
        }
      } else if (message.isBeacon) {
        // Got a beacon - device is already in service mode!
        subscription.cancel();
        if (!completer.isCompleted) {
          _rawLogController.add('[INFO] Device already in service mode');
          completer.complete(true);
        }
      }
    });

    // Spam the command until deadline or success
    while (DateTime.now().isBefore(deadline) && !completer.isCompleted) {
      attempt++;

      // Send command without waiting for response (fire and forget)
      _sendCommandNoWait(ServiceModeCommand.enterServiceMode);

      // Wait before next attempt
      await Future.delayed(interval);
    }

    // Clean up if we didn't get a response
    if (!completer.isCompleted) {
      subscription.cancel();
      _rawLogController.add('[ERROR] Failed to enter service mode after $attempt attempts');
      return false;
    }

    return await completer.future;
  }

  /// Send a command without waiting for response (fire and forget)
  void _sendCommandNoWait(ServiceModeCommand command) {
    if (!_isConnected || _port == null) return;

    try {
      final jsonString = command.toJsonString();
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      _port!.write(bytes);
    } catch (e) {
      // Ignore errors during rapid fire
    }
  }

  /// Exit service mode and continue to standard operation
  Future<bool> exitServiceMode() async {
    final response = await sendCommand(ServiceModeCommand.exitServiceMode);
    if (response?.isSuccess ?? false) {
      _rawLogController.add('[INFO] Exited service mode');
      return true;
    }
    _rawLogController.add('[ERROR] Failed to exit service mode: ${response?.message}');
    return false;
  }

  // ============================================
  // Status & Diagnostics
  // ============================================

  /// Get device status
  Future<DeviceInfo?> getStatus() async {
    final response = await sendCommand(
      ServiceModeCommand.getStatus,
      timeout: ServiceModeTimeouts.beaconPoll,
    );

    if (response?.isSuccess ?? false) {
      return response!.statusInfo;
    }
    return null;
  }

  /// Get device manifest
  Future<ServiceModeManifest?> getManifest() async {
    final response = await sendCommand(
      ServiceModeCommand.getManifest,
      timeout: ServiceModeTimeouts.standardCommand,
    );

    if (response?.isSuccess ?? false) {
      return response!.manifestData;
    }
    return null;
  }

  /// Wait for a beacon message (device in service mode)
  Future<DeviceInfo?> waitForBeacon({
    Duration timeout = ServiceModeTimeouts.beaconPoll,
  }) async {
    if (!_isConnected) return null;

    final completer = Completer<DeviceInfo?>();

    late StreamSubscription<DeviceInfo> subscription;
    Timer? timeoutTimer;

    subscription = beaconStream.listen((info) {
      timeoutTimer?.cancel();
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.complete(info);
      }
    });

    timeoutTimer = Timer(timeout, () {
      subscription.cancel();
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    return await completer.future;
  }

  // ============================================
  // Provisioning
  // ============================================

  /// Provision device with credentials
  Future<bool> provision({
    required String unitId,
    String? cloudUrl,
    String? cloudAnonKey,
    String? cloudDeviceSecret,
    Map<String, dynamic>? additionalData,
  }) async {
    if (!_isConnected || _port == null) {
      _rawLogController.add('[ERROR] Not connected');
      return false;
    }

    final command = ServiceModeCommand.provision(
      unitId: unitId,
      cloudUrl: cloudUrl,
      cloudAnonKey: cloudAnonKey,
      cloudDeviceSecret: cloudDeviceSecret,
      additionalData: additionalData,
    );

    final jsonString = command.toJsonString();
    _rawLogController.add('[TX] ${jsonString.trim()}');

    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      _port!.write(bytes);

      // Wait for either JSON response or log-based success indicators
      final completer = Completer<bool>();

      late StreamSubscription<ServiceModeMessage> messageSubscription;
      late StreamSubscription<String> logSubscription;
      Timer? timeoutTimer;

      // Listen for JSON response (preferred)
      messageSubscription = messageStream.listen((message) {
        if (message.status == ServiceModeStatus.provisioned) {
          timeoutTimer?.cancel();
          messageSubscription.cancel();
          logSubscription.cancel();
          if (!completer.isCompleted) {
            _rawLogController.add('[INFO] Device provisioned successfully');
            completer.complete(true);
          }
        } else if (message.isError) {
          timeoutTimer?.cancel();
          messageSubscription.cancel();
          logSubscription.cancel();
          if (!completer.isCompleted) {
            final errorMsg = ServiceModeErrorCodes.getMessage(message.errorCode);
            _rawLogController.add('[ERROR] Provisioning failed: $errorMsg');
            completer.complete(false);
          }
        }
      });

      // Listen for ESP-IDF log lines as fallback success indicator
      logSubscription = rawLogStream.listen((logLine) {
        if (logLine.contains('Device marked as provisioned') ||
            logLine.contains('Factory provisioning complete') ||
            logLine.contains('Provisioning complete')) {
          timeoutTimer?.cancel();
          messageSubscription.cancel();
          logSubscription.cancel();
          if (!completer.isCompleted) {
            _rawLogController.add('[INFO] Provisioning confirmed via device logs');
            completer.complete(true);
          }
        }
      });

      timeoutTimer = Timer(ServiceModeTimeouts.standardCommand, () {
        messageSubscription.cancel();
        logSubscription.cancel();
        if (!completer.isCompleted) {
          _rawLogController.add('[TIMEOUT] No provisioning confirmation received');
          completer.complete(false);
        }
      });

      return await completer.future;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to send provision command', e, stackTrace);
      _rawLogController.add('[ERROR] Failed to send: $e');
      return false;
    }
  }

  // ============================================
  // Testing
  // ============================================

  /// Run a single test
  Future<TestResult> runTest(
    String testName, {
    Map<String, dynamic>? testData,
  }) async {
    final startTime = DateTime.now();
    _rawLogController.add('[TEST] Running test_$testName...');

    final command = ServiceModeCommand.test(testName, testData);
    final timeout = ServiceModeTimeouts.getTestTimeout(testName);

    final response = await sendCommand(command, timeout: timeout);
    final duration = DateTime.now().difference(startTime);

    if (response == null) {
      return TestResult(
        testId: testName,
        status: TestStatus.failed,
        message: 'Timeout waiting for response',
        timestamp: DateTime.now(),
        duration: duration,
      );
    }

    final status =
        response.isSuccess ? TestStatus.passed : TestStatus.failed;

    return TestResult(
      testId: testName,
      status: status,
      message: response.message,
      data: response.data,
      timestamp: DateTime.now(),
      duration: duration,
    );
  }

  /// Run Wi-Fi test with optional credentials
  Future<TestResult> testWifi({String? ssid, String? password}) async {
    final startTime = DateTime.now();
    _rawLogController.add('[TEST] Running test_wifi...');

    final command = ServiceModeCommand.testWifi(ssid: ssid, password: password);
    final response =
        await sendCommand(command, timeout: ServiceModeTimeouts.wifiTest);
    final duration = DateTime.now().difference(startTime);

    if (response == null) {
      return TestResult(
        testId: 'wifi',
        status: TestStatus.failed,
        message: 'Timeout waiting for response',
        timestamp: DateTime.now(),
        duration: duration,
      );
    }

    return TestResult(
      testId: 'wifi',
      status: response.isSuccess ? TestStatus.passed : TestStatus.failed,
      message: response.message,
      data: response.data,
      timestamp: DateTime.now(),
      duration: duration,
    );
  }

  /// Run all tests
  Future<TestResult> testAll({String? wifiSsid, String? wifiPassword}) async {
    final startTime = DateTime.now();
    _rawLogController.add('[TEST] Running test_all...');

    final command =
        ServiceModeCommand.testAll(wifiSsid: wifiSsid, wifiPassword: wifiPassword);
    final response =
        await sendCommand(command, timeout: ServiceModeTimeouts.testAll);
    final duration = DateTime.now().difference(startTime);

    if (response == null) {
      return TestResult(
        testId: 'all',
        status: TestStatus.failed,
        message: 'Timeout waiting for response',
        timestamp: DateTime.now(),
        duration: duration,
      );
    }

    // Check if all tests passed
    final allPassed = response.data?['all_passed'] as bool? ?? false;

    return TestResult(
      testId: 'all',
      status: allPassed ? TestStatus.passed : TestStatus.failed,
      message: response.message,
      data: response.data,
      timestamp: DateTime.now(),
      duration: duration,
    );
  }

  // ============================================
  // Reset Operations
  // ============================================

  /// Customer reset (clear user data, preserve provisioning)
  Future<bool> customerReset() async {
    _rawLogController.add('[INFO] Executing customer reset...');
    final response = await sendCommand(ServiceModeCommand.customerReset);
    if (response?.isSuccess ?? false) {
      _rawLogController.add('[INFO] Customer reset complete - device will reboot');
      return true;
    }
    _rawLogController.add('[ERROR] Customer reset failed: ${response?.message}');
    return false;
  }

  /// Factory reset (full wipe including unit_id)
  Future<bool> factoryReset() async {
    _rawLogController.add('[INFO] Executing factory reset...');
    final response = await sendCommand(ServiceModeCommand.factoryReset);
    if (response?.isSuccess ?? false) {
      _rawLogController.add('[INFO] Factory reset complete - device will reboot');
      return true;
    }
    _rawLogController.add('[ERROR] Factory reset failed: ${response?.message}');
    return false;
  }

  /// Reboot device
  Future<bool> reboot() async {
    _rawLogController.add('[INFO] Rebooting device...');
    final response = await sendCommand(ServiceModeCommand.reboot);
    if (response?.isSuccess ?? false) {
      _rawLogController.add('[INFO] Device rebooting...');
      return true;
    }
    _rawLogController.add('[ERROR] Reboot failed: ${response?.message}');
    return false;
  }

  // ============================================
  // Custom Commands
  // ============================================

  /// Execute a custom command
  Future<ServiceModeMessage?> executeCustomCommand(
    String commandName, {
    Map<String, dynamic>? data,
    Duration timeout = ServiceModeTimeouts.standardCommand,
  }) async {
    _rawLogController.add('[INFO] Executing custom command: $commandName');
    return sendCommand(
      ServiceModeCommand.custom(commandName, data),
      timeout: timeout,
    );
  }

  // ============================================
  // Data Handling
  // ============================================

  /// Handle incoming serial data
  void _handleData(Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true);

    for (final char in text.runes) {
      if (char == 10 || char == 13) {
        // Newline
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
    // Log all lines
    _rawLogController.add('[RX] $line');

    // Filter ESP-IDF log lines (don't start with '{')
    if (!line.startsWith('{')) {
      return;
    }

    // Try to parse as JSON message
    final message = ServiceModeMessage.fromJsonLine(line);
    if (message != null) {
      _messageController.add(message);

      // If beacon, extract and emit device info
      if (message.isBeacon) {
        final beaconInfo = message.beaconInfo;
        if (beaconInfo != null) {
          _lastBeaconInfo = beaconInfo;
          _beaconController.add(beaconInfo);
        }
      }
    }
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _rawLogController.close();
    _beaconController.close();
    _connectionStateController.close();
  }
}
