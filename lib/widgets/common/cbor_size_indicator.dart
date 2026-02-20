import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/utils/cbor_size_estimator.dart';

/// Visual indicator for CBOR heartbeat payload size against the
/// 62-byte single 802.15.4 frame budget.
///
/// Color-codes by severity: green (ok), amber (warning), red (danger).
class CborSizeIndicator extends StatelessWidget {
  final CborSizeEstimate estimate;
  final String? label;

  /// If true, displays only the capability bytes contribution
  /// (without protocol overhead in the displayed value).
  final bool capabilityOnly;

  const CborSizeIndicator({
    super.key,
    required this.estimate,
    this.label,
    this.capabilityOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayBytes =
        capabilityOnly ? estimate.capabilityBytes : estimate.totalBytes;
    final maxBytes = estimate.maxBytes;
    final ratio = maxBytes > 0 ? displayBytes / maxBytes : 0.0;
    final color = _severityColor(estimate.severity);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.straighten, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label ?? 'CBOR Heartbeat Size',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              Text(
                '$displayBytes / $maxBytes bytes',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor:
                  SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitleText(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(CborSizeSeverity severity) {
    switch (severity) {
      case CborSizeSeverity.ok:
        return SaturdayColors.success;
      case CborSizeSeverity.warning:
        return SaturdayColors.warning;
      case CborSizeSeverity.danger:
        return SaturdayColors.error;
    }
  }

  String _subtitleText() {
    if (capabilityOnly) {
      return '${estimate.capabilityBytes}B capability fields'
          ' + ${estimate.protocolOverhead}B protocol overhead'
          ' = ${estimate.totalBytes}B total';
    }
    if (estimate.fitsInSingleFrame) {
      return '${estimate.remainingBytes} bytes remaining'
          ' (${estimate.protocolOverhead}B overhead'
          ' + ${estimate.capabilityBytes}B fields)';
    }
    return 'Exceeds single frame by ${-estimate.remainingBytes} bytes'
        ' \u2014 will require 6LoWPAN fragmentation';
  }
}

/// Per-capability contribution to the total heartbeat size.
class CapabilitySizeContribution {
  final String name;
  final int bytes;

  const CapabilitySizeContribution({
    required this.name,
    required this.bytes,
  });
}

/// Shows per-capability breakdown of heartbeat byte contributions.
///
/// Displays a compact stacked bar with each capability as a colored
/// segment, plus protocol overhead, followed by a legend.
class CborSizeBreakdown extends StatelessWidget {
  final List<CapabilitySizeContribution> contributions;
  final int protocolOverhead;
  final int maxBytes;

  const CborSizeBreakdown({
    super.key,
    required this.contributions,
    required this.protocolOverhead,
    required this.maxBytes,
  });

  // Consistent palette for capability segments.
  static const _segmentColors = [
    Color(0xFF6AC5F4), // info blue
    Color(0xFFF5A623), // amber
    Color(0xFF30AA47), // green
    Color(0xFFE06CC0), // pink
    Color(0xFF8B6CEF), // purple
    Color(0xFF4DD0E1), // teal
    Color(0xFFFF8A65), // orange
  ];

  @override
  Widget build(BuildContext context) {
    final activeContributions =
        contributions.where((c) => c.bytes > 0).toList();
    if (activeContributions.isEmpty) return const SizedBox.shrink();

    final totalBytes =
        activeContributions.fold<int>(0, (s, c) => s + c.bytes) +
            protocolOverhead;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Breakdown by capability',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
          const SizedBox(height: 6),
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 12,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  final scale =
                      maxBytes > 0 ? barWidth / maxBytes : 0.0;

                  return Stack(
                    children: [
                      // Background (remaining budget)
                      Container(
                        width: barWidth,
                        color: SaturdayColors.secondaryGrey
                            .withValues(alpha: 0.15),
                      ),
                      // Stacked segments
                      ..._buildSegments(
                          activeContributions, scale, barWidth),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Legend rows
          ...activeContributions.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            final color = _segmentColors[i % _segmentColors.length];
            final pct = totalBytes > 0
                ? (c.bytes / totalBytes * 100).round()
                : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      c.name,
                      style:
                          Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${c.bytes}B ($pct%)',
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                  ),
                ],
              ),
            );
          }),
          // Protocol overhead row
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: SaturdayColors.secondaryGrey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Protocol overhead',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ),
                Text(
                  '${protocolOverhead}B'
                  ' (${totalBytes > 0 ? (protocolOverhead / totalBytes * 100).round() : 0}%)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSegments(
    List<CapabilitySizeContribution> active,
    double scale,
    double barWidth,
  ) {
    final widgets = <Widget>[];
    double offset = 0;

    // Protocol overhead first (grey)
    final overheadWidth = (protocolOverhead * scale).clamp(0.0, barWidth);
    widgets.add(Positioned(
      left: offset,
      top: 0,
      bottom: 0,
      child: Container(
        width: overheadWidth,
        color: SaturdayColors.secondaryGrey.withValues(alpha: 0.4),
      ),
    ));
    offset += overheadWidth;

    // Capability segments
    for (var i = 0; i < active.length; i++) {
      final segWidth =
          (active[i].bytes * scale).clamp(0.0, barWidth - offset);
      final color = _segmentColors[i % _segmentColors.length];
      widgets.add(Positioned(
        left: offset,
        top: 0,
        bottom: 0,
        child: Container(width: segWidth, color: color),
      ));
      offset += segWidth;
    }

    return widgets;
  }
}
