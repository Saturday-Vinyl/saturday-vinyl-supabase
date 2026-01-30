import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';

/// Log line types for color coding
enum LogLineType {
  /// Transmitted data to device
  tx,
  /// Received response to a command (status: ok/error)
  rxResponse,
  /// Received data from device (general logs, heartbeats)
  rxData,
  /// Informational message
  info,
  /// Warning message
  warning,
  /// Error message
  error,
  /// Success message
  success,
  /// Timeout message
  timeout,
  /// Standard log line
  standard,
}

/// Widget for displaying serial communication logs
class LogDisplay extends StatelessWidget {
  final List<String> logLines;
  final ScrollController? scrollController;
  final bool hideBeacons;

  const LogDisplay({
    super.key,
    required this.logLines,
    this.scrollController,
    this.hideBeacons = false,
  });

  /// Check if a line is a service mode beacon
  static bool isBeaconLine(String line) {
    return line.contains('"status":"service_mode"');
  }

  @override
  Widget build(BuildContext context) {
    // Filter out beacon lines if hideBeacons is true
    final displayLines = hideBeacons
        ? logLines.where((line) => !isBeaconLine(line)).toList()
        : logLines;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: displayLines.isEmpty
          ? Center(
              child: Text(
                hideBeacons && logLines.isNotEmpty
                    ? 'All visible logs are beacons (hidden)'
                    : 'No logs yet. Connect to a device to see serial output.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
            )
          : ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: displayLines.length,
              itemBuilder: (context, index) {
                final line = displayLines[index];
                final lineType = _getLineType(line);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: _buildLogLine(line, lineType),
                );
              },
            ),
    );
  }

  Widget _buildLogLine(String line, LogLineType type) {
    final color = _getColorForType(type);
    final prefix = _getPrefixForType(type);
    final backgroundColor = _getBackgroundForType(type);

    return Container(
      padding: backgroundColor != null
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
          : null,
      decoration: backgroundColor != null
          ? BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(2),
            )
          : null,
      child: SelectableText.rich(
        TextSpan(
          children: [
            if (prefix != null)
              TextSpan(
                text: prefix,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            TextSpan(
              text: _stripPrefix(line),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  LogLineType _getLineType(String line) {
    // Check for TX (transmitted commands)
    if (line.startsWith('[TX]')) {
      return LogLineType.tx;
    }

    // Check for RX (received data)
    if (line.startsWith('[RX]')) {
      // Check if it's a response to a command (has status field)
      if (line.contains('"status"')) {
        return LogLineType.rxResponse;
      }
      return LogLineType.rxData;
    }

    // Check for tagged messages
    if (line.startsWith('[ERROR]')) {
      return LogLineType.error;
    }
    if (line.startsWith('[WARN]')) {
      return LogLineType.warning;
    }
    if (line.startsWith('[INFO]')) {
      return LogLineType.info;
    }
    if (line.startsWith('[SUCCESS]')) {
      return LogLineType.success;
    }
    if (line.startsWith('[TIMEOUT]')) {
      return LogLineType.timeout;
    }

    // Check content for keywords
    final lower = line.toLowerCase();
    if (lower.contains('error') || lower.contains('fail')) {
      return LogLineType.error;
    }
    if (lower.contains('success') || lower.contains('passed')) {
      return LogLineType.success;
    }
    if (lower.contains('warn')) {
      return LogLineType.warning;
    }

    return LogLineType.standard;
  }

  Color _getColorForType(LogLineType type) {
    switch (type) {
      case LogLineType.tx:
        return const Color(0xFFFFD700); // Gold - transmitted commands
      case LogLineType.rxResponse:
        return const Color(0xFF00FF7F); // Spring green - command responses
      case LogLineType.rxData:
        return const Color(0xFF87CEEB); // Sky blue - device data/heartbeats
      case LogLineType.info:
        return Colors.grey[400]!;
      case LogLineType.warning:
        return Colors.orange;
      case LogLineType.error:
        return SaturdayColors.error;
      case LogLineType.success:
        return SaturdayColors.success;
      case LogLineType.timeout:
        return Colors.orange[300]!;
      case LogLineType.standard:
        return Colors.grey[400]!;
    }
  }

  Color? _getBackgroundForType(LogLineType type) {
    switch (type) {
      case LogLineType.tx:
        return const Color(0xFFFFD700).withValues(alpha: 0.1);
      case LogLineType.rxResponse:
        return const Color(0xFF00FF7F).withValues(alpha: 0.1);
      case LogLineType.error:
        return SaturdayColors.error.withValues(alpha: 0.1);
      default:
        return null;
    }
  }

  String? _getPrefixForType(LogLineType type) {
    switch (type) {
      case LogLineType.tx:
        return '→ '; // Right arrow for TX
      case LogLineType.rxResponse:
        return '← '; // Left arrow for RX response
      case LogLineType.rxData:
        return '◀ '; // Small left arrow for RX data
      default:
        return null;
    }
  }

  String _stripPrefix(String line) {
    // Remove [TX], [RX], [INFO], etc. prefixes since we show arrows instead
    if (line.startsWith('[TX] ')) {
      return line.substring(5);
    }
    if (line.startsWith('[RX] ')) {
      return line.substring(5);
    }
    // Keep other prefixes like [INFO], [ERROR] for context
    return line;
  }
}
