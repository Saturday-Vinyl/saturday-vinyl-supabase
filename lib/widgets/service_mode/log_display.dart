import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';

/// Widget for displaying serial communication logs
class LogDisplay extends StatelessWidget {
  final List<String> logLines;
  final ScrollController? scrollController;

  const LogDisplay({
    super.key,
    required this.logLines,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: logLines.isEmpty
          ? Center(
              child: Text(
                'No logs yet. Connect to a device to see serial output.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
            )
          : ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: logLines.length,
              itemBuilder: (context, index) {
                final line = logLines[index];
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
