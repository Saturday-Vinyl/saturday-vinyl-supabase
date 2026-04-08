import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/models/heartbeat_chart_data.dart';
import 'package:saturday_app/providers/heartbeat_chart_provider.dart';
import 'package:saturday_app/widgets/heartbeat_chart/heartbeat_line_chart.dart';

/// Chart colors for each metric
const metricColors = {
  HeartbeatMetric.batteryLevel: Color(0xFF30AA47), // green
  HeartbeatMetric.freeHeap: Color(0xFF6AC5F4), // blue
  HeartbeatMetric.wifiRssi: Color(0xFFF5A623), // orange
  HeartbeatMetric.threadRssi: Color(0xFFAB6FE8), // purple
};

/// Telemetry chart section for unit detail screen
class HeartbeatChartSection extends ConsumerStatefulWidget {
  final String unitId;
  final List<Device> devices;

  const HeartbeatChartSection({
    super.key,
    required this.unitId,
    required this.devices,
  });

  @override
  ConsumerState<HeartbeatChartSection> createState() =>
      _HeartbeatChartSectionState();
}

class _HeartbeatChartSectionState extends ConsumerState<HeartbeatChartSection> {
  @override
  void initState() {
    super.initState();
    // Load data after first frame to avoid modifying providers during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(heartbeatChartProvider(widget.unitId).notifier)
          .loadData(widget.devices);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chartState = ref.watch(heartbeatChartProvider(widget.unitId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, chartState),
            const SizedBox(height: 16),
            _buildChart(context, chartState),
            if (chartState.availableMetrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildLegend(context, chartState),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, HeartbeatChartState chartState) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Telemetry',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: chartState.isLoading
              ? null
              : () => ref
                  .read(heartbeatChartProvider(widget.unitId).notifier)
                  .loadData(widget.devices),
          tooltip: 'Refresh',
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 8),
        // Time range selector
        SegmentedButton<ChartTimeRange>(
          segments: ChartTimeRange.values
              .map((range) => ButtonSegment(
                    value: range,
                    label: Text(range.label),
                  ))
              .toList(),
          selected: {chartState.timeRange},
          onSelectionChanged: (selected) {
            ref
                .read(heartbeatChartProvider(widget.unitId).notifier)
                .setTimeRange(selected.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChart(BuildContext context, HeartbeatChartState chartState) {
    if (chartState.isLoading) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (chartState.error != null) {
      return SizedBox(
        height: 250,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 32, color: SaturdayColors.error),
              const SizedBox(height: 8),
              Text(
                chartState.error!,
                style: TextStyle(color: SaturdayColors.error, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!chartState.hasData) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(
            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.show_chart,
                size: 40,
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'No heartbeat data for this time range',
                style: TextStyle(
                  color: SaturdayColors.secondaryGrey,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 250,
      child: HeartbeatLineChart(
        unitId: widget.unitId,
        devices: widget.devices,
      ),
    );
  }

  Widget _buildLegend(BuildContext context, HeartbeatChartState chartState) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: HeartbeatMetric.values
          .where((m) => chartState.availableMetrics.contains(m))
          .map((metric) {
        final isEnabled = chartState.enabledMetrics.contains(metric);
        final color = metricColors[metric]!;

        return FilterChip(
          selected: isEnabled,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? color
                      : color.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${metric.label} (${metric.unit})',
                style: TextStyle(
                  fontSize: 11,
                  color: isEnabled
                      ? SaturdayColors.primaryDark
                      : SaturdayColors.secondaryGrey,
                ),
              ),
            ],
          ),
          onSelected: (_) {
            ref
                .read(heartbeatChartProvider(widget.unitId).notifier)
                .toggleMetric(metric);
          },
          showCheckmark: false,
          selectedColor: color.withValues(alpha: 0.15),
          backgroundColor: Colors.grey.shade100,
          side: BorderSide(
            color: isEnabled ? color : Colors.grey.shade300,
          ),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      }).toList(),
    );
  }
}
