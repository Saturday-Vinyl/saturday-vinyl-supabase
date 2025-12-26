import 'dart:async';
import 'package:flutter/services.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Service for detecting and handling keyboard events from USB scanners
/// and manual keyboard shortcuts for QR code scanning
class KeyboardListenerService {
  // Prefix options for scanner detection
  // Scanner sends F4 key when programmed with EM (ASCII 25) barcode
  static final prefixChar = String.fromCharCode(25); // EM barcode (translates to F4 key)
  static const prefixKey = LogicalKeyboardKey.f4; // F4 function key
  static const scanDetectionDelayMs = 100; // Time to detect scanner vs manual
  static const bufferTimeoutSeconds = 2; // Overall timeout to clear buffer

  // State management
  final StringBuffer _scanBuffer = StringBuffer();
  Timer? _delayTimer;
  Timer? _timeoutTimer;
  bool _prefixDetected = false;

  // Callbacks
  Function(String scannedData)? onScanDetected;
  Function()? onManualShortcut;

  /// Handle keyboard events
  /// Returns true if event was handled, false to pass to other handlers
  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return false; // Only process key down events
    }

    // Detect Ctrl+Shift+Q keyboard shortcut
    if (event.logicalKey == LogicalKeyboardKey.keyQ &&
        HardwareKeyboard.instance.isControlPressed &&
        HardwareKeyboard.instance.isShiftPressed) {
      AppLogger.info('Keyboard shortcut detected: Ctrl+Shift+Q');
      _onPrefixDetected();
      return true; // Event handled
    }

    // Detect F4 prefix key (sent by scanner when programmed with EM barcode)
    if (event.logicalKey == prefixKey) {
      AppLogger.info('Prefix key detected: F4 (from scanner EM barcode)');
      _onPrefixDetected();
      return true; // Don't pass to text fields
    }

    // If prefix detected, buffer subsequent characters
    if (_prefixDetected && event.character != null) {
      _bufferCharacter(event.character!);
      return true; // Don't pass to text fields
    }

    return false; // Let other handlers process
  }

  /// Called when prefix is detected (either keyboard shortcut or § character)
  void _onPrefixDetected() {
    _prefixDetected = true;
    _scanBuffer.clear();

    // Cancel any existing timers
    _delayTimer?.cancel();
    _timeoutTimer?.cancel();

    // Start 100ms delay timer to detect scanner vs manual input
    _delayTimer = Timer(const Duration(milliseconds: scanDetectionDelayMs), () {
      if (_scanBuffer.isEmpty) {
        // No characters received within delay period → Manual keyboard shortcut
        AppLogger.info('Manual keyboard shortcut detected (no characters within ${scanDetectionDelayMs}ms)');
        onManualShortcut?.call();
        _reset();
      } else {
        // Characters received → USB scanner detected, continue buffering until Enter
        AppLogger.info('USB scanner detected (characters received within ${scanDetectionDelayMs}ms)');
      }
    });

    // Start overall 2-second timeout
    _timeoutTimer = Timer(const Duration(seconds: bufferTimeoutSeconds), () {
      AppLogger.warning('Buffer timeout reached, resetting state');
      _reset();
    });
  }

  /// Buffer a character from the keyboard
  void _bufferCharacter(String char) {
    // Check if Enter key pressed (end of scan)
    if (char == '\n' || char == '\r') {
      AppLogger.info('Enter key detected, processing buffered scan');
      _processBufferedScan();
    } else {
      // Add character to buffer
      _scanBuffer.write(char);
      AppLogger.debug('Buffered character, current buffer length: ${_scanBuffer.length}');
    }
  }

  /// Process the buffered scan data
  void _processBufferedScan() {
    final scannedData = _scanBuffer.toString().trim();

    if (scannedData.isEmpty) {
      AppLogger.warning('Buffered scan is empty, ignoring');
      _reset();
      return;
    }

    AppLogger.info('Processing buffered scan: $scannedData');

    // Cancel timers
    _delayTimer?.cancel();
    _timeoutTimer?.cancel();

    // Call callback with scanned data
    onScanDetected?.call(scannedData);

    // Reset state
    _reset();
  }

  /// Reset state to ready for next scan
  void _reset() {
    _scanBuffer.clear();
    _prefixDetected = false;
    _delayTimer?.cancel();
    _timeoutTimer?.cancel();
  }

  /// Cleanup resources
  void dispose() {
    _delayTimer?.cancel();
    _timeoutTimer?.cancel();
    _scanBuffer.clear();
    AppLogger.info('KeyboardListenerService disposed');
  }
}
