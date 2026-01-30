import 'dart:async';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/services/device_communication_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for monitoring USB serial ports and detecting Saturday devices.
///
/// This service runs as a global monitor, polling for serial port changes
/// and probing new ports to identify Saturday devices. When a device is
/// detected, it emits events that can be used to update the UI.
///
/// Usage:
/// ```dart
/// final monitor = USBMonitorService();
/// monitor.eventStream.listen((event) {
///   if (event.type == USBDeviceEventType.deviceIdentified) {
///     print('Found device: ${event.device?.macAddress}');
///   }
/// });
/// await monitor.startMonitoring();
/// ```
class USBMonitorService {
  static const Duration _pollInterval = Duration(seconds: 2);

  Timer? _pollTimer;
  bool _isMonitoring = false;
  Set<String> _knownPorts = {};

  /// Map of port name to connected device info
  final Map<String, ConnectedDevice> _connectedDevices = {};

  /// Ports currently being probed (to avoid duplicate probes)
  final Set<String> _probingPorts = {};

  final _eventController = StreamController<USBDeviceEvent>.broadcast();

  /// Stream of USB device events
  Stream<USBDeviceEvent> get eventStream => _eventController.stream;

  /// Map of currently connected Saturday devices (port name -> device)
  Map<String, ConnectedDevice> get connectedDevices =>
      Map.unmodifiable(_connectedDevices);

  /// Whether the monitor is currently running
  bool get isMonitoring => _isMonitoring;

  /// Number of connected Saturday devices
  int get deviceCount => _connectedDevices.length;

  /// Start monitoring for USB device changes
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    AppLogger.info('USBMonitorService: Starting port monitoring');

    // Get initial port list
    _knownPorts = _getAvailablePorts();
    AppLogger.info(
        'USBMonitorService: Found ${_knownPorts.length} initial ports: $_knownPorts');

    // Probe existing ports for Saturday devices
    for (final port in _knownPorts) {
      AppLogger.info('USBMonitorService: Probing port: $port');
      await _probePort(port);
    }

    AppLogger.info('USBMonitorService: Initial probe complete. Found ${_connectedDevices.length} Saturday device(s)');

    // Start polling for changes
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkForChanges());
  }

  /// Stop monitoring
  void stopMonitoring() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isMonitoring = false;
    _knownPorts.clear();
    _connectedDevices.clear();
    _probingPorts.clear();
    AppLogger.info('USBMonitorService: Stopped port monitoring');
  }

  /// Force a refresh of connected devices
  Future<void> refreshDevices() async {
    if (!_isMonitoring) return;

    AppLogger.info('USBMonitorService: Refreshing devices');

    // Clear current device list
    final previousDevices = Map<String, ConnectedDevice>.from(_connectedDevices);
    _connectedDevices.clear();

    // Get current ports and probe each
    _knownPorts = _getAvailablePorts();

    for (final port in _knownPorts) {
      await _probePort(port);
    }

    // Emit disconnect events for devices that are no longer present
    for (final entry in previousDevices.entries) {
      if (!_connectedDevices.containsKey(entry.key)) {
        _eventController.add(USBDeviceEvent(
          type: USBDeviceEventType.deviceDisconnected,
          portName: entry.key,
          device: entry.value,
        ));
      }
    }
  }

  /// Get a device by its MAC address
  ConnectedDevice? getDeviceByMac(String macAddress) {
    final normalizedMac = macAddress.toUpperCase();
    return _connectedDevices.values.firstWhereOrNull(
      (d) => d.macAddress.toUpperCase() == normalizedMac,
    );
  }

  /// Get a device by its serial number
  ConnectedDevice? getDeviceBySerialNumber(String serialNumber) {
    return _connectedDevices.values.firstWhereOrNull(
      (d) => d.serialNumber == serialNumber,
    );
  }

  /// Check if a specific port has a Saturday device
  bool hasDeviceOnPort(String portName) {
    return _connectedDevices.containsKey(portName);
  }

  Set<String> _getAvailablePorts() {
    try {
      return SerialPort.availablePorts.toSet();
    } catch (e) {
      AppLogger.error('USBMonitorService: Failed to get available ports', e);
      return {};
    }
  }

  Future<void> _checkForChanges() async {
    final currentPorts = _getAvailablePorts();

    // Find added ports
    final addedPorts = currentPorts.difference(_knownPorts);
    for (final port in addedPorts) {
      AppLogger.info('USBMonitorService: Port added: $port');
      _eventController.add(USBDeviceEvent(
        type: USBDeviceEventType.portAdded,
        portName: port,
      ));
      await _probePort(port);
    }

    // Find removed ports
    final removedPorts = _knownPorts.difference(currentPorts);
    for (final port in removedPorts) {
      AppLogger.info('USBMonitorService: Port removed: $port');
      _eventController.add(USBDeviceEvent(
        type: USBDeviceEventType.portRemoved,
        portName: port,
      ));

      // If we had a device on this port, emit disconnect event
      final device = _connectedDevices.remove(port);
      if (device != null) {
        _eventController.add(USBDeviceEvent(
          type: USBDeviceEventType.deviceDisconnected,
          portName: port,
          device: device,
        ));
      }
    }

    _knownPorts = currentPorts;
  }

  Future<void> _probePort(String portName) async {
    // Skip if already probing this port
    if (_probingPorts.contains(portName)) return;

    // Skip common non-device ports
    if (_shouldSkipPort(portName)) {
      AppLogger.debug('USBMonitorService: Skipping non-device port: $portName');
      return;
    }

    _probingPorts.add(portName);

    try {
      AppLogger.debug('USBMonitorService: Probing port: $portName');
      final device = await DeviceCommunicationService.probePort(portName);

      if (device != null) {
        AppLogger.info(
            'USBMonitorService: Identified Saturday device on $portName: '
            '${device.deviceType} (${device.macAddress})');

        _connectedDevices[portName] = device;
        _eventController.add(USBDeviceEvent(
          type: USBDeviceEventType.deviceIdentified,
          portName: portName,
          device: device,
        ));
      } else {
        AppLogger.debug(
            'USBMonitorService: Port $portName is not a Saturday device');
        _eventController.add(USBDeviceEvent(
          type: USBDeviceEventType.identificationFailed,
          portName: portName,
          error: 'No Saturday device response',
        ));
      }
    } catch (e) {
      AppLogger.debug('USBMonitorService: Probe failed for $portName: $e');
      _eventController.add(USBDeviceEvent(
        type: USBDeviceEventType.identificationFailed,
        portName: portName,
        error: e.toString(),
      ));
    } finally {
      _probingPorts.remove(portName);
    }
  }

  /// Check if a port should be skipped (common non-device ports)
  bool _shouldSkipPort(String portName) {
    final lowerName = portName.toLowerCase();

    // Skip Bluetooth ports
    if (lowerName.contains('bluetooth')) return true;

    // Skip internal/debug ports on macOS
    if (lowerName.contains('debug-console')) return true;
    if (lowerName.contains('wlan-debug')) return true;

    // Skip standard modem ports that aren't USB serial devices
    if (lowerName == '/dev/tty.modem') return true;

    return false;
  }

  /// Dispose the service
  void dispose() {
    stopMonitoring();
    _eventController.close();
  }
}

/// Extension to add firstWhereOrNull to Iterable
extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
