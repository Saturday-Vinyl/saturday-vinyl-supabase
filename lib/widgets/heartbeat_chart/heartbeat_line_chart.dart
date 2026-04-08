import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/models/heartbeat_chart_data.dart';
import 'package:saturday_app/providers/heartbeat_chart_provider.dart';
import 'package:saturday_app/widgets/heartbeat_chart/heartbeat_chart_section.dart';

/// The fl_chart LineChart rendering heartbeat telemetry with dual Y-axes
class HeartbeatLineChart extends ConsumerWidget {
  final String unitId;
  final List<Device> devices;

  const HeartbeatLineChart({
    super.key,
    required this.unitId,
    required this.devices,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartState = ref.watch(heartbeatChartProvider(unitId));
    final enabledMetrics = chartState.enabledMetrics
        .intersection(chartState.availableMetrics);

    if (enabledMetrics.isEmpty) {
      return Center(
        child: Text(
          'Select a metric to display',
          style: TextStyle(
            color: SaturdayColors.secondaryGrey,
            fontSize: 13,
          ),
        ),
      );
    }

    // Compute time bounds
    final now = DateTime.now();
    final since = now.subtract(chartState.timeRange.duration);
    final minX = since.millisecondsSinceEpoch.toDouble();
    final maxX = now.millisecondsSinceEpoch.toDouble();

    // Build line chart bar data from segments
    final lineBars = <LineChartBarData>[];
    _buildLineBars(chartState, enabledMetrics, lineBars);

    // Compute Y-axis bounds
    final yBounds = _computeYBounds(chartState, enabledMetrics);

    // Build event overlay lines
    final extraLines = _buildEventLines(chartState, minX, maxX);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: yBounds.minY,
          maxY: yBounds.maxY,
          lineBarsData: lineBars,
          extraLinesData: ExtraLinesData(verticalLines: extraLines),
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: true,
            horizontalInterval: yBounds.gridInterval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (_) => FlLine(
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
              strokeWidth: 1,
            ),
          ),
          titlesData: _buildTitles(chartState, yBounds, minX, maxX),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3)),
              left: BorderSide(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3)),
            ),
          ),
          lineTouchData: _buildTouchData(enabledMetrics),
        ),
        duration: const Duration(milliseconds: 150),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Line bars
  // --------------------------------------------------------------------------

  void _buildLineBars(
    HeartbeatChartState chartState,
    Set<HeartbeatMetric> enabledMetrics,
    List<LineChartBarData> lineBars,
  ) {
    for (final entry in chartState.segments.entries) {
      final segments = entry.value;

      for (final metric in enabledMetrics) {
        final color = metricColors[metric]!;

        // Each contiguous segment becomes its own LineChartBarData
        for (final segment in segments) {
          final spots = <FlSpot>[];
          for (final point in segment) {
            final value = point.valueFor(metric);
            if (value != null) {
              spots.add(FlSpot(
                point.timestamp.millisecondsSinceEpoch.toDouble(),
                value,
              ));
            }
          }

          if (spots.length >= 2) {
            lineBars.add(LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              curveSmoothness: 0.2,
              color: color,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ));
          } else if (spots.length == 1) {
            // Single point: show as a dot
            lineBars.add(LineChartBarData(
              spots: spots,
              isCurved: false,
              color: color,
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3,
                  color: color,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ));
          }
        }
      }
    }
  }

  // --------------------------------------------------------------------------
  // Y-axis bounds
  // --------------------------------------------------------------------------

  _YBounds _computeYBounds(
    HeartbeatChartState chartState,
    Set<HeartbeatMetric> enabledMetrics,
  ) {
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final points in chartState.dataPoints.values) {
      for (final point in points) {
        for (final metric in enabledMetrics) {
          final value = point.valueFor(metric);
          if (value != null) {
            minY = math.min(minY, value);
            maxY = math.max(maxY, value);
          }
        }
      }
    }

    if (minY == double.infinity) {
      return const _YBounds(0, 100, 25);
    }

    // Add padding
    final range = maxY - minY;
    final padding = range * 0.1;
    minY = minY - padding;
    maxY = maxY + padding;

    // For battery (0-100%), clamp
    if (enabledMetrics.length == 1 &&
        enabledMetrics.contains(HeartbeatMetric.batteryLevel)) {
      minY = 0;
      maxY = 100;
      return _YBounds(minY, maxY, 25);
    }

    // Compute nice grid interval
    final interval = _niceInterval(maxY - minY);

    return _YBounds(minY, maxY, interval);
  }

  double _niceInterval(double range) {
    if (range <= 0) return 25;
    final rawInterval = range / 5;
    final magnitude = math.pow(10, (math.log(rawInterval) / math.ln10).floor());
    final normalized = rawInterval / magnitude;

    double niceValue;
    if (normalized <= 1.5) {
      niceValue = 1;
    } else if (normalized <= 3) {
      niceValue = 2;
    } else if (normalized <= 7) {
      niceValue = 5;
    } else {
      niceValue = 10;
    }
    return (niceValue * magnitude).toDouble();
  }

  // --------------------------------------------------------------------------
  // Event overlay lines (restarts + RFID)
  // --------------------------------------------------------------------------

  List<VerticalLine> _buildEventLines(
    HeartbeatChartState chartState,
    double minX,
    double maxX,
  ) {
    return chartState.eventMarkers.map((marker) {
      final x = marker.timestamp.millisecondsSinceEpoch.toDouble();
      if (x < minX || x > maxX) return null;

      Color color;
      List<int> dashPattern;
      String shortLabel;
      double strokeWidth;

      switch (marker.type) {
        case ChartEventType.brownoutLoop:
          color = SaturdayColors.error;
          dashPattern = [2, 2];
          shortLabel = 'BO';
          strokeWidth = 2;
        case ChartEventType.restart:
          // Color by severity if the label contains a reason
          final isCritical = marker.label.contains('Brownout') ||
              marker.label.contains('Panic') ||
              marker.label.contains('WDT');
          color = isCritical
              ? SaturdayColors.error
              : SaturdayColors.warning;
          dashPattern = [4, 4];
          shortLabel = marker.label.contains('x restarts')
              ? marker.label.split(' ').first // e.g. "5"
              : 'R';
          strokeWidth = 1;
        case ChartEventType.rfidScan:
          color = SaturdayColors.success;
          dashPattern = [2, 3];
          shortLabel = 'S';
          strokeWidth = 1;
      }

      return VerticalLine(
        x: x,
        color: color.withValues(alpha: 0.6),
        strokeWidth: strokeWidth,
        dashArray: dashPattern,
        label: VerticalLineLabel(
          show: true,
          alignment: Alignment.topCenter,
          style: TextStyle(
            fontSize: 8,
            color: color,
            fontWeight: FontWeight.w500,
          ),
          labelResolver: (_) => shortLabel,
        ),
      );
    }).whereType<VerticalLine>().toList();
  }

  // --------------------------------------------------------------------------
  // Axis titles
  // --------------------------------------------------------------------------

  FlTitlesData _buildTitles(
    HeartbeatChartState chartState,
    _YBounds yBounds,
    double minX,
    double maxX,
  ) {
    final timeFormat = chartState.timeRange == ChartTimeRange.twentyFourHours
        ? DateFormat('HH:mm\nMM/dd')
        : DateFormat('HH:mm');

    // Show ~5-6 labels on the X axis
    final xRange = maxX - minX;
    final xInterval = xRange / 5;

    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: xInterval,
          reservedSize: 32,
          getTitlesWidget: (value, meta) {
            // Skip edge labels that would overlap
            if (value == meta.min || value == meta.max) {
              return const SizedBox.shrink();
            }
            final dt =
                DateTime.fromMillisecondsSinceEpoch(value.toInt());
            return SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text(
                timeFormat.format(dt),
                style: const TextStyle(fontSize: 9),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: yBounds.gridInterval,
          reservedSize: 48,
          getTitlesWidget: (value, meta) {
            if (value == meta.min || value == meta.max) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text(
                _formatYValue(value),
                style: const TextStyle(fontSize: 9),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatYValue(double value) {
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  // --------------------------------------------------------------------------
  // Touch / tooltip
  // --------------------------------------------------------------------------

  LineTouchData _buildTouchData(Set<HeartbeatMetric> enabledMetrics) {
    return LineTouchData(
      enabled: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) =>
            SaturdayColors.primaryDark.withValues(alpha: 0.9),
        tooltipRoundedRadius: 8,
        maxContentWidth: 200,
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            final dt = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
            final timeStr = DateFormat('HH:mm:ss').format(dt);

            // Find which metric this line belongs to by color
            final lineColor = spot.bar.color;
            HeartbeatMetric? metric;
            for (final m in enabledMetrics) {
              if (metricColors[m] == lineColor) {
                metric = m;
                break;
              }
            }

            final valueStr = metric == HeartbeatMetric.freeHeap
                ? '${spot.y.toStringAsFixed(1)} KB'
                : '${spot.y.toInt()} ${metric?.unit ?? ''}';

            return LineTooltipItem(
              '$timeStr\n${metric?.label ?? ''}: $valueStr',
              const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1.4,
              ),
            );
          }).toList();
        },
      ),
      handleBuiltInTouches: true,
    );
  }
}

// --------------------------------------------------------------------------
// Helper types
// --------------------------------------------------------------------------

class _YBounds {
  final double minY;
  final double maxY;
  final double gridInterval;
  const _YBounds(this.minY, this.maxY, this.gridInterval);
}
