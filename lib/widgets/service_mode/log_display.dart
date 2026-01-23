import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';

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
                return SelectableText(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _getColorForLine(line),
                  ),
                );
              },
            ),
    );
  }

  Color _getColorForLine(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('error') || lower.contains('fail')) {
      return SaturdayColors.error;
    }
    if (lower.contains('success') || lower.contains('passed')) {
      return SaturdayColors.success;
    }
    if (lower.contains('warn')) {
      return Colors.orange;
    }
    if (line.startsWith('{') || line.startsWith('>')) {
      return Colors.cyan;
    }
    if (line.startsWith('<')) {
      return Colors.greenAccent;
    }
    return Colors.grey[400]!;
  }
}
