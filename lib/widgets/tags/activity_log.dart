import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/activity_log_entry.dart';
import 'package:saturday_app/providers/activity_log_provider.dart';

/// Expandable activity log panel for displaying real-time operation feedback
class ActivityLog extends ConsumerStatefulWidget {
  final bool initiallyExpanded;
  final ValueChanged<String>? onEpcTap;

  const ActivityLog({
    super.key,
    this.initiallyExpanded = true,
    this.onEpcTap,
  });

  @override
  ConsumerState<ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends ConsumerState<ActivityLog> {
  late bool _isExpanded;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(activityLogDisplayProvider);

    // Auto-scroll when new entries are added
    ref.listen<List<ActivityLogEntry>>(activityLogDisplayProvider,
        (previous, next) {
      if (previous != null &&
          next.length > previous.length &&
          _isExpanded) {
        _scrollToBottom();
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(entries.length),

          // Log content (when expanded)
          if (_isExpanded) _buildLogContent(entries),
        ],
      ),
    );
  }

  Widget _buildHeader(int entryCount) {
    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
        if (_isExpanded) {
          _scrollToBottom();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              _isExpanded
                  ? Icons.expand_more
                  : Icons.chevron_right,
              size: 20,
              color: SaturdayColors.secondaryGrey,
            ),
            const SizedBox(width: 8),
            Text(
              'Activity Log',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: SaturdayColors.primaryDark,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$entryCount',
                style: TextStyle(
                  fontSize: 12,
                  color: SaturdayColors.secondaryGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
            if (entryCount > 0)
              TextButton.icon(
                onPressed: () {
                  ref.read(activityLogProvider.notifier).clear();
                },
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: SaturdayColors.secondaryGrey,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogContent(List<ActivityLogEntry> entries) {
    if (entries.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Text(
          'No activity yet',
          style: TextStyle(
            color: SaturdayColors.secondaryGrey,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: SaturdayColors.light.withValues(alpha: 0.3),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          return _ActivityLogEntryItem(
            entry: entries[index],
            onEpcTap: widget.onEpcTap,
          );
        },
      ),
    );
  }
}

/// Individual activity log entry item
class _ActivityLogEntryItem extends StatelessWidget {
  final ActivityLogEntry entry;
  final ValueChanged<String>? onEpcTap;

  const _ActivityLogEntryItem({
    required this.entry,
    this.onEpcTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: entry.relatedEpc != null && onEpcTap != null
          ? () => onEpcTap!(entry.relatedEpc!)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timestamp
            SizedBox(
              width: 70,
              child: Text(
                DateFormat('HH:mm:ss').format(entry.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: SaturdayColors.secondaryGrey,
                ),
              ),
            ),

            // Level icon
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildLevelIcon(),
            ),

            // Message
            Expanded(
              child: Text(
                entry.message,
                style: TextStyle(
                  fontSize: 13,
                  color: _getTextColor(),
                ),
              ),
            ),

            // EPC link indicator
            if (entry.relatedEpc != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.link,
                  size: 14,
                  color: SaturdayColors.info,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelIcon() {
    IconData icon;
    Color color;

    switch (entry.level) {
      case LogLevel.info:
        icon = Icons.info_outline;
        color = SaturdayColors.info;
      case LogLevel.success:
        icon = Icons.check_circle_outline;
        color = SaturdayColors.success;
      case LogLevel.warning:
        icon = Icons.warning_amber_outlined;
        color = Colors.orange;
      case LogLevel.error:
        icon = Icons.error_outline;
        color = SaturdayColors.error;
    }

    return Icon(icon, size: 16, color: color);
  }

  Color _getTextColor() {
    switch (entry.level) {
      case LogLevel.info:
        return SaturdayColors.primaryDark;
      case LogLevel.success:
        return SaturdayColors.success;
      case LogLevel.warning:
        return Colors.orange.shade800;
      case LogLevel.error:
        return SaturdayColors.error;
    }
  }
}

/// Compact activity log indicator for showing in headers
class ActivityLogIndicator extends ConsumerWidget {
  final VoidCallback? onTap;

  const ActivityLogIndicator({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(activityLogProvider);
    final hasErrors = entries.any((e) => e.level == LogLevel.error);
    final hasWarnings = entries.any((e) => e.level == LogLevel.warning);

    Color indicatorColor;
    if (hasErrors) {
      indicatorColor = SaturdayColors.error;
    } else if (hasWarnings) {
      indicatorColor = Colors.orange;
    } else if (entries.isNotEmpty) {
      indicatorColor = SaturdayColors.success;
    } else {
      indicatorColor = SaturdayColors.secondaryGrey;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: indicatorColor,
              ),
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                '${entries.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: SaturdayColors.secondaryGrey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
