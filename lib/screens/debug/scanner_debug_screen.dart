import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/services/keyboard_listener_service.dart';

/// Debug screen to visualize scanner input and keyboard events
class ScannerDebugScreen extends StatefulWidget {
  const ScannerDebugScreen({super.key});

  @override
  State<ScannerDebugScreen> createState() => _ScannerDebugScreenState();
}

class _ScannerDebugScreenState extends State<ScannerDebugScreen> {
  final List<KeyEventInfo> _keyEvents = [];
  final ScrollController _scrollController = ScrollController();
  bool _isListening = true;

  @override
  void initState() {
    super.initState();
    ServicesBinding.instance.keyboard.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleKeyEvent);
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!_isListening || event is! KeyDownEvent) {
      return false;
    }

    setState(() {
      _keyEvents.add(KeyEventInfo(
        timestamp: DateTime.now(),
        logicalKey: event.logicalKey.keyLabel,
        character: event.character,
        keyCode: event.logicalKey.keyId,
        isPrefixKey: event.logicalKey == KeyboardListenerService.prefixKey,
      ));
    });

    // Auto-scroll to bottom
    Timer(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    return false; // Don't consume the event, let it propagate
  }

  void _clearLog() {
    setState(() {
      _keyEvents.clear();
    });
  }

  void _toggleListening() {
    setState(() {
      _isListening = !_isListening;
    });
  }

  String _getCharacterDisplay(String? char) {
    if (char == null || char.isEmpty) {
      return '(none)';
    }

    // Check for special control characters
    final code = char.codeUnits.first;
    if (code < 32) {
      return _getControlCharName(code);
    }
    if (code == 127) {
      return 'DEL';
    }

    return char;
  }

  String _getControlCharName(int code) {
    const controlChars = {
      0: 'NUL',
      1: 'SOH',
      2: 'STX',
      3: 'ETX',
      4: 'EOT',
      5: 'ENQ',
      6: 'ACK',
      7: 'BEL',
      8: 'BS',
      9: 'HT (Tab)',
      10: 'LF',
      11: 'VT',
      12: 'FF',
      13: 'CR (Enter)',
      14: 'SO',
      15: 'SI',
      16: 'DLE',
      17: 'DC1',
      18: 'DC2',
      19: 'DC3',
      20: 'DC4',
      21: 'NAK',
      22: 'SYN',
      23: 'ETB',
      24: 'CAN',
      25: 'EM',
      26: 'SUB',
      27: 'ESC',
      28: 'FS',
      29: 'GS',
      30: 'RS',
      31: 'US',
    };
    return controlChars[code] ?? 'CTRL-$code';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner Debug'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isListening ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleListening,
            tooltip: _isListening ? 'Pause' : 'Resume',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearLog,
            tooltip: 'Clear Log',
          ),
        ],
      ),
      body: Column(
        children: [
          // Info Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: SaturdayColors.info.withValues(alpha: 0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: SaturdayColors.info),
                    const SizedBox(width: 8),
                    Text(
                      'Scanner Debug Mode',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: SaturdayColors.info,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Scan a QR code or type on your keyboard. All key events will be logged below. '
                  'Look for "F4 (Prefix!)" to confirm your scanner is sending the correct prefix key.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Expected prefix: F4 key (from EM barcode)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SaturdayColors.success,
                      ),
                ),
              ],
            ),
          ),

          // Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: _isListening
                ? SaturdayColors.success.withValues(alpha: 0.1)
                : SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  _isListening ? Icons.radio_button_checked : Icons.pause_circle,
                  color: _isListening ? SaturdayColors.success : SaturdayColors.secondaryGrey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isListening ? 'Listening...' : 'Paused',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _isListening ? SaturdayColors.success : SaturdayColors.secondaryGrey,
                      ),
                ),
                const Spacer(),
                Text(
                  '${_keyEvents.length} events logged',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Key Events List
          Expanded(
            child: _keyEvents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.keyboard,
                          size: 64,
                          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Waiting for keyboard input...',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: SaturdayColors.secondaryGrey,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try scanning a QR code with your scanner',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SaturdayColors.secondaryGrey,
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _keyEvents.length,
                    itemBuilder: (context, index) {
                      final event = _keyEvents[index];
                      final isPrefix = event.isPrefixKey;

                      return Card(
                        elevation: isPrefix ? 4 : 1,
                        color: isPrefix
                            ? SaturdayColors.success.withValues(alpha: 0.1)
                            : null,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Timestamp and key label
                              Row(
                                children: [
                                  Text(
                                    '${event.timestamp.hour.toString().padLeft(2, '0')}:'
                                    '${event.timestamp.minute.toString().padLeft(2, '0')}:'
                                    '${event.timestamp.second.toString().padLeft(2, '0')}.'
                                    '${event.timestamp.millisecond.toString().padLeft(3, '0')}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontFamily: 'monospace',
                                          color: SaturdayColors.secondaryGrey,
                                        ),
                                  ),
                                  const Spacer(),
                                  if (isPrefix)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: SaturdayColors.success,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'PREFIX DETECTED',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Character and ASCII code
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Character:',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: SaturdayColors.secondaryGrey,
                                              ),
                                        ),
                                        Text(
                                          isPrefix
                                              ? 'F4 (Prefix!)'
                                              : _getCharacterDisplay(event.character),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                                color: isPrefix
                                                    ? SaturdayColors.success
                                                    : null,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isPrefix ? 'Key Code:' : 'ASCII Code:',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: SaturdayColors.secondaryGrey,
                                              ),
                                        ),
                                        Text(
                                          isPrefix
                                              ? 'F4'
                                              : (event.character != null &&
                                                      event.character!.isNotEmpty
                                                  ? event.character!.codeUnits.first
                                                      .toString()
                                                  : 'N/A'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.bold,
                                                color: isPrefix
                                                    ? SaturdayColors.success
                                                    : null,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Key label
                              const SizedBox(height: 8),
                              Text(
                                'Key: ${event.logicalKey}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: SaturdayColors.secondaryGrey,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Information about a keyboard event
class KeyEventInfo {
  final DateTime timestamp;
  final String logicalKey;
  final String? character;
  final int keyCode;
  final bool isPrefixKey;

  KeyEventInfo({
    required this.timestamp,
    required this.logicalKey,
    required this.character,
    required this.keyCode,
    this.isPrefixKey = false,
  });
}
