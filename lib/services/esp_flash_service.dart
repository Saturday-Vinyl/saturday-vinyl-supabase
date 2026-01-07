import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Result of a firmware flash operation
class FlashResult {
  final bool success;
  final String? macAddress;
  final String? errorMessage;
  final List<String> logs;

  const FlashResult({
    required this.success,
    this.macAddress,
    this.errorMessage,
    required this.logs,
  });
}

/// Service for flashing ESP32 firmware using esptool
class EspFlashService {
  static const String _esptoolCommand = 'esptool.py';
  static const String _esptoolAltCommand = 'esptool';
  static const int _defaultBaudRate = 460800;
  // Default offset for merged binaries (bootloader + partition table + app)
  // Use 0x10000 for app-only binaries if bootloader is already flashed
  static const int _defaultFlashOffset = 0x0;

  final _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;

  Process? _currentProcess;
  bool _isCancelled = false;
  String? _esptoolPath;

  /// Check if esptool is available on the system
  Future<bool> isEsptoolAvailable() async {
    // List of paths to check - includes common Homebrew locations
    // since macOS GUI apps don't inherit shell PATH
    final pathsToCheck = [
      _esptoolCommand,
      _esptoolAltCommand,
      '/opt/homebrew/bin/esptool.py', // Homebrew on Apple Silicon
      '/opt/homebrew/bin/esptool',
      '/usr/local/bin/esptool.py', // Homebrew on Intel
      '/usr/local/bin/esptool',
    ];

    for (final path in pathsToCheck) {
      try {
        final result = await Process.run(path, ['version']);
        if (result.exitCode == 0) {
          _esptoolPath = path;
          AppLogger.info('Found esptool at: $path');
          return true;
        }
      } catch (e) {
        // Try next path
      }
    }

    AppLogger.warning('esptool not found in any known location');
    return false;
  }

  /// Get esptool version string
  Future<String?> getEsptoolVersion() async {
    if (_esptoolPath == null) {
      final available = await isEsptoolAvailable();
      if (!available) return null;
    }

    try {
      final result = await Process.run(_esptoolPath!, ['version']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim().split('\n').first;
      }
    } catch (e) {
      AppLogger.error('Failed to get esptool version', e);
    }

    return null;
  }

  /// Get list of available serial ports for flashing
  List<String> getAvailablePorts() {
    return SerialPort.availablePorts;
  }

  /// Get detailed info about a serial port
  Map<String, String> getPortInfo(String portName) {
    try {
      final port = SerialPort(portName);
      final info = <String, String>{
        'Port': portName,
        'Description': port.description ?? '',
        'Manufacturer': port.manufacturer ?? '',
        'Serial Number': port.serialNumber ?? '',
        'Product ID': port.productId?.toRadixString(16) ?? '',
        'Vendor ID': port.vendorId?.toRadixString(16) ?? '',
      };
      port.dispose();
      return info;
    } catch (e) {
      return {'Port': portName, 'Error': e.toString()};
    }
  }

  /// Flash firmware to ESP32
  ///
  /// [binaryPath] - Local path to the firmware binary
  /// [port] - Serial port (e.g., /dev/tty.usbserial-0001)
  /// [chipType] - ESP32 chip type (esp32, esp32s2, esp32s3, esp32c3, esp32c6, esp32h2)
  /// [flashOffset] - Flash address offset (default: 0x0)
  /// [baudRate] - Baud rate for flashing (default: 460800)
  Future<FlashResult> flashFirmware({
    required String binaryPath,
    required String port,
    required String chipType,
    int flashOffset = _defaultFlashOffset,
    int baudRate = _defaultBaudRate,
  }) async {
    _isCancelled = false;
    final logs = <String>[];

    // Check esptool availability
    if (_esptoolPath == null) {
      final available = await isEsptoolAvailable();
      if (!available) {
        const error = 'esptool not found. Please install esptool.py';
        _logController.add('[ERROR] $error');
        return FlashResult(
          success: false,
          errorMessage: error,
          logs: [error],
        );
      }
    }

    // Verify binary file exists
    final binaryFile = File(binaryPath);
    if (!await binaryFile.exists()) {
      final error = 'Firmware binary not found: $binaryPath';
      _logController.add('[ERROR] $error');
      return FlashResult(
        success: false,
        errorMessage: error,
        logs: [error],
      );
    }

    // Build esptool command
    final args = [
      '--chip', chipType,
      '--port', port,
      '--baud', baudRate.toString(),
      'write_flash',
      '0x${flashOffset.toRadixString(16)}',
      binaryPath,
    ];

    _logController.add('[CMD] $_esptoolPath ${args.join(' ')}');
    logs.add('Command: $_esptoolPath ${args.join(' ')}');

    try {
      _currentProcess = await Process.start(
        _esptoolPath!,
        args,
        mode: ProcessStartMode.normal,
      );

      String? extractedMacAddress;
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // Stream stdout
      _currentProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (_isCancelled) return;
        stdoutBuffer.writeln(line);
        logs.add(line);
        _logController.add(line);

        // Try to extract MAC address from output
        final mac = _extractMacAddress(line);
        if (mac != null) {
          extractedMacAddress = mac;
          _logController.add('[INFO] Detected MAC: $mac');
        }
      });

      // Stream stderr
      _currentProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (_isCancelled) return;
        stderrBuffer.writeln(line);
        logs.add('[ERR] $line');
        _logController.add('[ERR] $line');
      });

      // Wait for process to complete
      final exitCode = await _currentProcess!.exitCode;

      if (_isCancelled) {
        return FlashResult(
          success: false,
          errorMessage: 'Flashing cancelled',
          logs: logs,
        );
      }

      if (exitCode == 0) {
        _logController.add('[SUCCESS] Firmware flashed successfully');
        return FlashResult(
          success: true,
          macAddress: extractedMacAddress,
          logs: logs,
        );
      } else {
        final error = 'esptool exited with code $exitCode';
        _logController.add('[ERROR] $error');
        return FlashResult(
          success: false,
          errorMessage: error,
          logs: logs,
        );
      }
    } catch (e, stackTrace) {
      final error = 'Failed to run esptool: $e';
      _logController.add('[ERROR] $error');
      AppLogger.error(error, e, stackTrace);
      return FlashResult(
        success: false,
        errorMessage: error,
        logs: logs,
      );
    } finally {
      _currentProcess = null;
    }
  }

  /// Read chip info (includes MAC address)
  Future<FlashResult> readChipInfo({
    required String port,
    required String chipType,
  }) async {
    _isCancelled = false;
    final logs = <String>[];

    if (_esptoolPath == null) {
      final available = await isEsptoolAvailable();
      if (!available) {
        const error = 'esptool not found';
        return FlashResult(success: false, errorMessage: error, logs: [error]);
      }
    }

    final args = [
      '--chip', chipType,
      '--port', port,
      'chip_id',
    ];

    _logController.add('[CMD] $_esptoolPath ${args.join(' ')}');

    try {
      _currentProcess = await Process.start(_esptoolPath!, args);

      String? extractedMacAddress;

      _currentProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        logs.add(line);
        _logController.add(line);

        final mac = _extractMacAddress(line);
        if (mac != null) {
          extractedMacAddress = mac;
        }
      });

      _currentProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        logs.add('[ERR] $line');
        _logController.add('[ERR] $line');
      });

      final exitCode = await _currentProcess!.exitCode;

      return FlashResult(
        success: exitCode == 0,
        macAddress: extractedMacAddress,
        errorMessage: exitCode != 0 ? 'chip_id failed with code $exitCode' : null,
        logs: logs,
      );
    } catch (e) {
      final error = 'Failed to read chip info: $e';
      return FlashResult(success: false, errorMessage: error, logs: logs);
    } finally {
      _currentProcess = null;
    }
  }

  /// Cancel current flashing operation
  void cancel() {
    _isCancelled = true;
    _currentProcess?.kill();
    _logController.add('[INFO] Flashing cancelled by user');
  }

  /// Extract MAC address from esptool output
  ///
  /// Esptool outputs MAC in format: "MAC: XX:XX:XX:XX:XX:XX"
  String? _extractMacAddress(String line) {
    // Pattern: MAC: followed by 6 hex pairs separated by colons
    final macPattern = RegExp(r'MAC:\s*([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})');
    final match = macPattern.firstMatch(line);
    if (match != null) {
      return match.group(1)?.toUpperCase();
    }
    return null;
  }

  void dispose() {
    cancel();
    _logController.close();
  }
}
