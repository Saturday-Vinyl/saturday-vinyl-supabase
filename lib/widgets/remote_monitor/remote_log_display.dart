import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:saturday_app/models/remote_log_entry.dart';

/// Widget for displaying remote device logs (heartbeats + commands)
///
/// Similar to the local LogDisplay but adapted for remote log entries.
class RemoteLogDisplay extends StatelessWidget {
  final List<RemoteLogEntry> entries;
  final ScrollController? scrollController;
  final bool showTimestamps;

  const RemoteLogDisplay({
    super.key,
    required this.entries,
    this.scrollController,
    this.showTimestamps = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: entries.isEmpty
          ? Center(
              child: Text(
                'No logs yet. Start monitoring to see device activity.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                ),
              ),
            )
          : ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: _buildLogLine(entry),
                );
              },
            ),
    );
  }

  Widget _buildLogLine(RemoteLogEntry entry) {
    final color = _getColorForType(entry.type);
    final backgroundColor = _getBackgroundForType(entry.type);
    final prefix = _getPrefixForType(entry.type);

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
            // Timestamp
            if (showTimestamps)
              TextSpan(
                text: '${_formatTime(entry.timestamp)} ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            // Prefix/arrow
            TextSpan(
              text: prefix,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            // Content
            TextSpan(
              text: entry.displayText,
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

  Color _getColorForType(RemoteLogEntryType type) {
    switch (type) {
      case RemoteLogEntryType.heartbeat:
        return const Color(0xFF87CEEB); // Sky blue
      case RemoteLogEntryType.commandSent:
        return const Color(0xFFFFD700); // Gold
      case RemoteLogEntryType.commandAck:
        return const Color(0xFF90EE90); // Light green
      case RemoteLogEntryType.commandResult:
        return const Color(0xFF00FF7F); // Spring green
    }
  }

  Color? _getBackgroundForType(RemoteLogEntryType type) {
    switch (type) {
      case RemoteLogEntryType.commandSent:
        return const Color(0xFFFFD700).withValues(alpha: 0.1);
      case RemoteLogEntryType.commandResult:
        return const Color(0xFF00FF7F).withValues(alpha: 0.1);
      default:
        return null;
    }
  }

  String _getPrefixForType(RemoteLogEntryType type) {
    switch (type) {
      case RemoteLogEntryType.heartbeat:
        return '◀ ';
      case RemoteLogEntryType.commandSent:
        return '→ ';
      case RemoteLogEntryType.commandAck:
        return '✓ ';
      case RemoteLogEntryType.commandResult:
        return '← ';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}

/// Widget for displaying expandable log entry details
class ExpandableLogEntry extends StatefulWidget {
  final RemoteLogEntry entry;
  final bool showTimestamp;

  const ExpandableLogEntry({
    super.key,
    required this.entry,
    this.showTimestamp = true,
  });

  @override
  State<ExpandableLogEntry> createState() => _ExpandableLogEntryState();
}

class _ExpandableLogEntryState extends State<ExpandableLogEntry> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final color = _getColorForType(entry.type);

    return GestureDetector(
      onTap: entry.data.isNotEmpty ? () => setState(() => _isExpanded = !_isExpanded) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isExpanded ? Colors.grey[850] : null,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.showTimestamp)
                  Text(
                    '${_formatTime(entry.timestamp)} ',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                Text(
                  _getPrefixForType(entry.type),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.displayText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.data.isNotEmpty)
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.grey[600],
                  ),
              ],
            ),
            if (_isExpanded && entry.data.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(entry.data),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getColorForType(RemoteLogEntryType type) {
    switch (type) {
      case RemoteLogEntryType.heartbeat:
        return const Color(0xFF87CEEB);
      case RemoteLogEntryType.commandSent:
        return const Color(0xFFFFD700);
      case RemoteLogEntryType.commandAck:
        return const Color(0xFF90EE90);
      case RemoteLogEntryType.commandResult:
        return const Color(0xFF00FF7F);
    }
  }

  String _getPrefixForType(RemoteLogEntryType type) {
    switch (type) {
      case RemoteLogEntryType.heartbeat:
        return '◀ ';
      case RemoteLogEntryType.commandSent:
        return '→ ';
      case RemoteLogEntryType.commandAck:
        return '✓ ';
      case RemoteLogEntryType.commandResult:
        return '← ';
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
