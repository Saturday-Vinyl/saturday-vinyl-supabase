import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:saturday_app/services/grbl_error_codes.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Machine connection status
enum MachineConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Machine state (combines connection status with operational state)
enum MachineState {
  disconnected,
  connecting,
  connected,
  idle,
  running,
  paused,
  alarm,
  error,
}

extension MachineStateExtension on MachineState {
  /// Get display name for the state
  String get displayName {
    switch (this) {
      case MachineState.disconnected:
        return 'Disconnected';
      case MachineState.connecting:
        return 'Connecting';
      case MachineState.connected:
        return 'Connected';
      case MachineState.idle:
        return 'Idle';
      case MachineState.running:
        return 'Running';
      case MachineState.paused:
        return 'Paused';
      case MachineState.alarm:
        return 'Alarm';
      case MachineState.error:
        return 'Error';
    }
  }
}

/// Machine type for connection configuration
enum MachineType {
  cnc('CNC Milling'),
  laser('Laser Cutting');

  const MachineType(this.displayName);
  final String displayName;
}

/// Machine status information
class MachineStatus {
  final String state; // Idle, Run, Hold, Alarm, etc.
  final double? xPosition;
  final double? yPosition;
  final double? zPosition;
  final int? feedRate;
  final int? spindleSpeed;

  MachineStatus({
    required this.state,
    this.xPosition,
    this.yPosition,
    this.zPosition,
    this.feedRate,
    this.spindleSpeed,
  });

  @override
  String toString() => 'MachineStatus(state: $state, pos: ($xPosition, $yPosition, $zPosition))';
}

/// Machine error event
class MachineErrorEvent {
  final GrblError error;
  final DateTime timestamp;

  MachineErrorEvent({
    required this.error,
    required this.timestamp,
  });

  @override
  String toString() => 'MachineError(code: ${error.code}, message: ${error.userMessage})';
}

/// Machine alarm event
class MachineAlarmEvent {
  final GrblAlarm alarm;
  final DateTime timestamp;

  MachineAlarmEvent({
    required this.alarm,
    required this.timestamp,
  });

  @override
  String toString() => 'MachineAlarm(code: ${alarm.code}, message: ${alarm.userMessage})';
}

/// Service for managing serial port connections to CNC/Laser machines
class MachineConnectionService {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readerSubscription;

  MachineConnectionStatus _status = MachineConnectionStatus.disconnected;
  MachineState _state = MachineState.disconnected;
  String? _connectedPortName;
  MachineType? _connectedMachineType;

  final _statusController = StreamController<MachineConnectionStatus>.broadcast();
  final _stateController = StreamController<MachineState>.broadcast();
  final _responseController = StreamController<String>.broadcast();
  final _machineStatusController = StreamController<MachineStatus>.broadcast();
  final _errorController = StreamController<MachineErrorEvent>.broadcast();
  final _alarmController = StreamController<MachineAlarmEvent>.broadcast();

  StringBuffer _lineBuffer = StringBuffer();

  // Reduce logging during heavy operations
  int _commandsSent = 0;
  bool _verboseLogging = true;
  String? _lastCommand; // Track last command for error context

  /// Stream of connection status changes
  Stream<MachineConnectionStatus> get statusStream => _statusController.stream;

  /// Stream of machine state changes
  Stream<MachineState> get stateStream => _stateController.stream;

  /// Stream of responses from the machine
  Stream<String> get responseStream => _responseController.stream;

  /// Stream of machine status updates
  Stream<MachineStatus> get machineStatusStream => _machineStatusController.stream;

  /// Stream of machine errors
  Stream<MachineErrorEvent> get errorStream => _errorController.stream;

  /// Stream of machine alarms
  Stream<MachineAlarmEvent> get alarmStream => _alarmController.stream;

  /// Current connection status
  MachineConnectionStatus get status => _status;

  /// Current machine state
  MachineState get state => _state;

  /// Currently connected port name
  String? get connectedPortName => _connectedPortName;

  /// Currently connected machine type
  MachineType? get connectedMachineType => _connectedMachineType;

  /// Check if connected
  bool get isConnected => _status == MachineConnectionStatus.connected;

  /// Get list of available serial ports
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

  /// Get detailed information about a port
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

  /// Connect to a machine via serial port
  ///
  /// [portName] - Serial port name (e.g., '/dev/tty.usbserial', 'COM3')
  /// [machineType] - Type of machine (CNC or Laser)
  /// [baudRate] - Baud rate (default: 115200 for grbl/grblHAL)
  Future<bool> connect({
    required String portName,
    required MachineType machineType,
    int baudRate = 115200,
  }) async {
    if (_status == MachineConnectionStatus.connected) {
      AppLogger.warning('Already connected to $_connectedPortName');
      return false;
    }

    _updateStatus(MachineConnectionStatus.connecting);

    try {
      AppLogger.info('Connecting to $machineType machine on $portName at $baudRate baud');

      _port = SerialPort(portName);

      // Open the port first
      if (!_port!.openReadWrite()) {
        final error = SerialPort.lastError;
        throw Exception('Failed to open port: ${error?.message}');
      }

      // Small delay to allow macOS to stabilize the port
      await Future.delayed(const Duration(milliseconds: 50));

      // Configure serial port for grbl/grblHAL after opening
      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      _port!.config = config;

      // Set up reader
      _reader = SerialPortReader(_port!);
      _lineBuffer = StringBuffer();

      _readerSubscription = _reader!.stream.listen(
        _handleIncomingData,
        onError: (error) {
          AppLogger.error('Serial port read error', error, null);
          _updateStatus(MachineConnectionStatus.error);
        },
        onDone: () {
          AppLogger.info('Serial port reader closed');
          disconnect();
        },
      );

      _connectedPortName = portName;
      _connectedMachineType = machineType;
      _updateStatus(MachineConnectionStatus.connected);
      _updateMachineState(MachineState.connected);

      AppLogger.info('Successfully connected to $machineType machine on $portName');

      // Send initial soft reset to grbl
      await Future.delayed(const Duration(milliseconds: 100));
      await sendCommand('\x18'); // Ctrl-X soft reset

      return true;
    } catch (error, stackTrace) {
      AppLogger.error('Error connecting to machine', error, stackTrace);
      _updateStatus(MachineConnectionStatus.error);
      await disconnect();
      return false;
    }
  }

  /// Disconnect from the machine
  Future<void> disconnect() async {
    AppLogger.info('Disconnecting from machine');

    try {
      await _readerSubscription?.cancel();
      _readerSubscription = null;

      _reader?.close();
      _reader = null;

      _port?.close();
      _port?.dispose();
      _port = null;

      _connectedPortName = null;
      _connectedMachineType = null;
      _lineBuffer.clear();

      _updateStatus(MachineConnectionStatus.disconnected);
      _updateMachineState(MachineState.disconnected);

      AppLogger.info('Disconnected from machine');
    } catch (error, stackTrace) {
      AppLogger.error('Error during disconnect', error, stackTrace);
    }
  }

  /// Send a command to the machine
  ///
  /// Returns true if command was sent successfully
  Future<bool> sendCommand(String command) async {
    if (!isConnected || _port == null) {
      // Always log connection errors
      AppLogger.warning('Cannot send command: not connected (command: ${command.trim()})');
      return false;
    }

    try {
      final commandWithNewline = command.endsWith('\n') ? command : '$command\n';
      final bytes = Uint8List.fromList(commandWithNewline.codeUnits);

      final written = _port!.write(bytes);

      if (written == bytes.length) {
        _commandsSent++;
        _lastCommand = command.trim(); // Track for error context
        // Only log every 100 commands when verbose logging is disabled
        if (_verboseLogging || _commandsSent % 100 == 0) {
          AppLogger.debug('Sent command #$_commandsSent: ${command.trim()}');
        }
        return true;
      } else {
        // Always log incomplete writes, even with verbose logging off
        AppLogger.warning(
          'Incomplete write on command #$_commandsSent: sent $written/${bytes.length} bytes for command: ${command.trim()}',
        );
        return false;
      }
    } catch (error, stackTrace) {
      // Always log exceptions, even with verbose logging off
      AppLogger.error(
        'Error sending command #$_commandsSent: ${command.trim()}',
        error,
        stackTrace,
      );
      return false;
    }
  }

  /// Enable or disable verbose logging (useful for high-volume operations)
  void setVerboseLogging(bool enabled) {
    _verboseLogging = enabled;
    if (enabled) {
      AppLogger.info('Verbose logging enabled');
    } else {
      AppLogger.info('Verbose logging disabled for performance');
    }
  }

  /// Request machine status (grbl '?' command)
  Future<void> requestStatus() async {
    await sendCommand('?');
  }

  /// Send feed hold (pause) command
  Future<void> feedHold() async {
    await sendCommand('!');
    AppLogger.info('Feed hold sent');
  }

  /// Send cycle start (resume) command
  Future<void> cycleStart() async {
    await sendCommand('~');
    AppLogger.info('Cycle start sent');
  }

  /// Send emergency stop (soft reset)
  Future<void> emergencyStop() async {
    await sendCommand('\x18'); // Ctrl-X
    AppLogger.warning('Emergency stop sent');
  }

  /// Send homing cycle command
  Future<bool> home() async {
    final success = await sendCommand('\$H');
    if (success) {
      AppLogger.info('Homing cycle started');
    }
    return success;
  }

  /// Zero current position (set work coordinate system)
  Future<bool> setZero({bool x = false, bool y = false, bool z = false}) async {
    final axes = [
      if (x) 'X0',
      if (y) 'Y0',
      if (z) 'Z0',
    ].join('');

    if (axes.isEmpty) {
      AppLogger.warning('No axes specified for zeroing');
      return false;
    }

    final success = await sendCommand('G10 L20 P0 $axes');
    if (success) {
      AppLogger.info('Zeroed position: $axes');
    }
    return success;
  }

  /// Handle incoming data from serial port
  void _handleIncomingData(Uint8List data) {
    try {
      final text = String.fromCharCodes(data);
      _lineBuffer.write(text);

      // Process complete lines
      final bufferText = _lineBuffer.toString();
      final lines = bufferText.split('\n');

      // Keep the last incomplete line in the buffer
      _lineBuffer.clear();
      if (!bufferText.endsWith('\n')) {
        _lineBuffer.write(lines.last);
        lines.removeLast();
      }

      // Process complete lines
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _processLine(trimmed);
        }
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error processing incoming data', error, stackTrace);
    }
  }

  /// Process a complete line from the machine
  void _processLine(String line) {
    // Throttle logging for high-volume operations
    // Always log errors, alarms, and important messages
    if (_verboseLogging ||
        line.startsWith('error:') ||
        line.startsWith('ALARM:') ||
        line.startsWith('Grbl') ||
        _commandsSent % 100 == 0) {
      AppLogger.debug('Received: $line');
    }
    _responseController.add(line);

    // Check for errors (format: error:9)
    final error = GrblErrorCodes.parseErrorResponse(line);
    if (error != null) {
      final errorEvent = MachineErrorEvent(
        error: error,
        timestamp: DateTime.now(),
      );
      _errorController.add(errorEvent);
      // Always log errors prominently, even with verbose logging disabled
      final lastCommandInfo = _lastCommand != null ? '\nLast command sent: $_lastCommand' : '';
      final errorMessage = 'GRBL ERROR ${error.code}: ${error.userMessage}\nTechnical: ${error.description}$lastCommandInfo';

      AppLogger.error(errorMessage, null, null);

      // Also use print() to ensure it shows in console
      // ignore: avoid_print
      print('\n\n========================================');
      // ignore: avoid_print
      print('GRBL ERROR ${error.code}: ${error.userMessage}');
      // ignore: avoid_print
      print('Technical: ${error.description}');
      if (_lastCommand != null) {
        // ignore: avoid_print
        print('Last command sent: $_lastCommand');
      }
      // ignore: avoid_print
      print('========================================\n\n');

      return;
    }

    // Check for alarms (format: ALARM:1)
    final alarm = GrblErrorCodes.parseAlarmResponse(line);
    if (alarm != null) {
      final alarmEvent = MachineAlarmEvent(
        alarm: alarm,
        timestamp: DateTime.now(),
      );
      _alarmController.add(alarmEvent);
      _updateMachineState(MachineState.alarm);
      // Always log alarms prominently, even with verbose logging disabled
      final lastCommandInfo = _lastCommand != null ? '\nLast command sent: $_lastCommand' : '';
      AppLogger.error(
        'GRBL ALARM ${alarm.code}: ${alarm.userMessage}\nTechnical: ${alarm.description}$lastCommandInfo',
        null,
        null,
      );
      return;
    }

    // Parse status reports (format: <Idle|MPos:0.000,0.000,0.000|FS:0,0>)
    if (line.startsWith('<') && line.endsWith('>')) {
      _parseStatusReport(line);
    }
  }

  /// Parse grbl status report
  void _parseStatusReport(String report) {
    try {
      // Remove < and >
      final content = report.substring(1, report.length - 1);
      final parts = content.split('|');

      if (parts.isEmpty) return;

      final state = parts[0];
      double? x, y, z;
      int? feedRate, spindleSpeed;

      for (final part in parts) {
        if (part.startsWith('MPos:') || part.startsWith('WPos:')) {
          final coords = part.substring(5).split(',');
          if (coords.length >= 3) {
            x = double.tryParse(coords[0]);
            y = double.tryParse(coords[1]);
            z = double.tryParse(coords[2]);
          }
        } else if (part.startsWith('FS:')) {
          final values = part.substring(3).split(',');
          if (values.length >= 2) {
            feedRate = int.tryParse(values[0]);
            spindleSpeed = int.tryParse(values[1]);
          }
        }
      }

      final status = MachineStatus(
        state: state,
        xPosition: x,
        yPosition: y,
        zPosition: z,
        feedRate: feedRate,
        spindleSpeed: spindleSpeed,
      );

      _machineStatusController.add(status);

      // Update machine state based on grbl state
      _updateMachineStateFromGrblState(state);
    } catch (error) {
      AppLogger.warning('Error parsing status report: $error');
    }
  }

  /// Update machine state based on grbl state string
  void _updateMachineStateFromGrblState(String grblState) {
    final stateUpper = grblState.toUpperCase();
    MachineState newState;

    if (stateUpper.contains('IDLE')) {
      newState = MachineState.idle;
    } else if (stateUpper.contains('RUN')) {
      newState = MachineState.running;
    } else if (stateUpper.contains('HOLD')) {
      newState = MachineState.paused;
    } else if (stateUpper.contains('ALARM')) {
      newState = MachineState.alarm;
    } else if (stateUpper.contains('ERROR')) {
      newState = MachineState.error;
    } else if (_status == MachineConnectionStatus.connected) {
      newState = MachineState.connected;
    } else if (_status == MachineConnectionStatus.connecting) {
      newState = MachineState.connecting;
    } else {
      newState = MachineState.disconnected;
    }

    _updateMachineState(newState);
  }

  /// Update machine state and notify listeners
  void _updateMachineState(MachineState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
      AppLogger.debug('Machine state: $_state');
    }
  }

  /// Update connection status and notify listeners
  void _updateStatus(MachineConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(_status);
      AppLogger.info('Machine connection status: $_status');
    }
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _statusController.close();
    _stateController.close();
    _responseController.close();
    _machineStatusController.close();
    _errorController.close();
    _alarmController.close();
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
