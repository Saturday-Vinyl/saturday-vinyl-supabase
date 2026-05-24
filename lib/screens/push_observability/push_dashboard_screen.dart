import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/push_observability.dart';
import 'package:saturday_app/providers/push_observability_provider.dart';
import 'package:saturday_app/repositories/push_observability_repository.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/push_observability/push_activity_row.dart';

/// Landing page for push notification observability.
///
/// Surfaces last-24h health, the 7-day time series, failure categories, and a
/// live activity feed driven by Supabase Realtime on notification_delivery_log.
class PushDashboardScreen extends ConsumerStatefulWidget {
  const PushDashboardScreen({super.key});

  @override
  ConsumerState<PushDashboardScreen> createState() =>
      _PushDashboardScreenState();
}

class _PushDashboardScreenState extends ConsumerState<PushDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushDeliveryTailProvider.notifier).startListening();
    });
  }

  @override
  void dispose() {
    // Realtime channel is owned by the StateNotifier; explicit stop keeps the
    // socket clean if the user navigates away.
    ref.read(pushDeliveryTailProvider.notifier).stopListening();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(pushStatsByTypeProvider);
    ref.invalidate(pushHealthBucketsProvider);
    ref.invalidate(pushErrorPatternsProvider);
    ref.invalidate(pushDeliveriesProvider);
    ref.read(pushDeliveryTailProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: const SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatsByTypeSection(),
              SizedBox(height: 24),
              _HealthChartSection(),
              SizedBox(height: 24),
              _ErrorPatternsSection(),
              SizedBox(height: 24),
              _LiveActivitySection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Stats by type
// ============================================================================

class _StatsByTypeSection extends ConsumerWidget {
  const _StatsByTypeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(pushStatsByTypeProvider);

    return _Section(
      title: 'Last 24 hours',
      subtitle:
          'Sent and failed counts grouped by notification type. Red border = >50% failure.',
      child: statsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: LoadingIndicator(),
        ),
        error: (error, _) => ErrorState(
          message: 'Failed to load stats',
          details: error.toString(),
        ),
        data: (stats) {
          if (stats.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_off_outlined,
              message: 'No push attempts in the last 24 hours',
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: stats.map((s) => _StatCard(stats: s)).toList(),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final PushTypeStats stats;
  const _StatCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final unhealthy = stats.total >= 10 && stats.failureRate > 0.5;
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unhealthy
              ? SaturdayColors.error
              : SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
          width: unhealthy ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stats.notificationType,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SaturdayColors.primaryDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unhealthy)
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: SaturdayColors.error),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricCell(
                label: 'Sent',
                value: stats.sent.toString(),
                color: SaturdayColors.success,
              ),
              const SizedBox(width: 16),
              _MetricCell(
                label: 'Failed',
                value: stats.failed.toString(),
                color: stats.failed > 0
                    ? SaturdayColors.error
                    : SaturdayColors.secondaryGrey,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${(stats.failureRate * 100).toStringAsFixed(1)}% failure rate',
            style: const TextStyle(
              fontSize: 11,
              color: SaturdayColors.secondaryGrey,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricCell({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: SaturdayColors.secondaryGrey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Health time-series chart
// ============================================================================

class _HealthChartSection extends ConsumerWidget {
  const _HealthChartSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucketsAsync = ref.watch(pushHealthBucketsProvider);
    return _Section(
      title: 'Delivery health (7 days, hourly)',
      subtitle:
          'Total sent vs failed per hour, across all notification types. A sudden gap in green or sustained red = investigate.',
      child: bucketsAsync.when(
        loading: () => const SizedBox(
          height: 220,
          child: LoadingIndicator(),
        ),
        error: (error, _) => ErrorState(
          message: 'Failed to load health buckets',
          details: error.toString(),
        ),
        data: (buckets) {
          if (buckets.isEmpty) {
            return const EmptyState(
              icon: Icons.show_chart,
              message: 'No delivery data in the last 7 days',
            );
          }
          return SizedBox(
            height: 240,
            child: _HealthChart(buckets: buckets),
          );
        },
      ),
    );
  }
}

class _HealthChart extends StatelessWidget {
  final List<PushHealthBucket> buckets;
  const _HealthChart({required this.buckets});

  @override
  Widget build(BuildContext context) {
    final byHour = <DateTime, _HourTotals>{};
    for (final b in buckets) {
      final totals = byHour.putIfAbsent(b.bucketHour, () => _HourTotals());
      totals.sent += b.sentCount;
      totals.failed += b.failedCount;
    }

    final hours = byHour.keys.toList()..sort();
    if (hours.isEmpty) {
      return const SizedBox.shrink();
    }
    final minX = hours.first.millisecondsSinceEpoch.toDouble();
    final maxX = hours.last.millisecondsSinceEpoch.toDouble();

    final sentSpots = <FlSpot>[];
    final failedSpots = <FlSpot>[];
    double maxY = 1;
    for (final h in hours) {
      final t = byHour[h]!;
      final x = h.millisecondsSinceEpoch.toDouble();
      sentSpots.add(FlSpot(x, t.sent.toDouble()));
      failedSpots.add(FlSpot(x, t.failed.toDouble()));
      if (t.sent > maxY) maxY = t.sent.toDouble();
      if (t.failed > maxY) maxY = t.failed.toDouble();
    }
    final yMax = (maxY * 1.2).ceilToDouble();

    return Padding(
      padding: const EdgeInsets.only(right: 12, top: 8),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: yMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (value, _) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: ((maxX - minX) / 6).clamp(3600000, double.infinity),
                getTitlesWidget: (value, _) {
                  final d =
                      DateTime.fromMillisecondsSinceEpoch(value.toInt());
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('M/d HH:mm').format(d),
                      style: const TextStyle(fontSize: 9),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3)),
              bottom: BorderSide(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3)),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: sentSpots,
              isCurved: false,
              color: SaturdayColors.success,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: failedSpots,
              isCurved: false,
              color: SaturdayColors.error,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => SaturdayColors.primaryDark,
              getTooltipItems: (spots) => spots.map((s) {
                final label = s.barIndex == 0 ? 'sent' : 'failed';
                return LineTooltipItem(
                  '${s.y.toInt()} $label',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _HourTotals {
  int sent = 0;
  int failed = 0;
}

// ============================================================================
// Error patterns table
// ============================================================================

class _ErrorPatternsSection extends ConsumerWidget {
  const _ErrorPatternsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patternsAsync = ref.watch(pushErrorPatternsProvider);
    return _Section(
      title: 'Failures by category (7 days)',
      subtitle:
          'Server-wide categories (auth, env mismatch) indicate credential issues — investigate before they snowball.',
      child: patternsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: LoadingIndicator(),
        ),
        error: (error, _) => ErrorState(
          message: 'Failed to load error patterns',
          details: error.toString(),
        ),
        data: (patterns) {
          if (patterns.isEmpty) {
            return const _EmptyOkState(
              message: 'No failures in the last 7 days',
            );
          }
          return _ErrorPatternsTable(patterns: patterns);
        },
      ),
    );
  }
}

class _ErrorPatternsTable extends StatelessWidget {
  final List<PushErrorPattern> patterns;
  const _ErrorPatternsTable({required this.patterns});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: SaturdayColors.primaryDark,
          ),
          dataTextStyle: const TextStyle(
            fontSize: 12,
            color: SaturdayColors.primaryDark,
          ),
          columnSpacing: 32,
          columns: const [
            DataColumn(label: Text('CATEGORY')),
            DataColumn(label: Text('TYPE')),
            DataColumn(label: Text('COUNT'), numeric: true),
            DataColumn(label: Text('TOKENS'), numeric: true),
            DataColumn(label: Text('USERS'), numeric: true),
            DataColumn(label: Text('FIRST SEEN')),
            DataColumn(label: Text('LAST SEEN')),
          ],
          rows: patterns.map((p) {
            return DataRow(
              color: p.isServerWide
                  ? WidgetStateProperty.all(
                      SaturdayColors.error.withValues(alpha: 0.07))
                  : null,
              cells: [
                DataCell(Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (p.isServerWide)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.dangerous_outlined,
                            size: 16, color: SaturdayColors.error),
                      ),
                    Text(p.errorCategory,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ],
                )),
                DataCell(Text(p.notificationType,
                    style: const TextStyle(fontFamily: 'monospace'))),
                DataCell(Text(p.n.toString())),
                DataCell(Text(p.affectedTokens.toString())),
                DataCell(Text(p.affectedUsers.toString())),
                DataCell(Text(_fmt(p.firstSeen))),
                DataCell(Text(_fmt(p.lastSeen))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ============================================================================
// Live activity feed
// ============================================================================

class _LiveActivitySection extends ConsumerWidget {
  const _LiveActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tail = ref.watch(pushDeliveryTailProvider).events;
    final feedAsync = ref.watch(pushDeliveriesProvider);

    return _Section(
      title: 'Live activity',
      subtitle:
          'Live tail (top) plus the most recent 200 attempts from the last 24h. New rows stream in via Realtime.',
      child: feedAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: LoadingIndicator(),
        ),
        error: (error, _) => ErrorState(
          message: 'Failed to load activity',
          details: error.toString(),
        ),
        data: (initial) {
          final merged = _mergeFeed(tail, initial);
          if (merged.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              message: 'No activity in the last 24 hours',
            );
          }
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                for (final d in merged.take(50))
                  PushActivityRow(delivery: d, isLive: tail.contains(d)),
              ],
            ),
          );
        },
      ),
    );
  }
}

List<PushDelivery> _mergeFeed(
    List<PushDelivery> tail, List<PushDelivery> initial) {
  final ids = <String>{};
  final out = <PushDelivery>[];
  for (final d in tail) {
    if (ids.add(d.id)) out.add(d);
  }
  for (final d in initial) {
    if (ids.add(d.id)) out.add(d);
  }
  return out;
}

// ============================================================================
// Section wrapper + helpers
// ============================================================================

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 12,
              color: SaturdayColors.secondaryGrey,
            ),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _EmptyOkState extends StatelessWidget {
  final String message;
  const _EmptyOkState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SaturdayColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: SaturdayColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: SaturdayColors.success, size: 18),
          const SizedBox(width: 8),
          Text(message,
              style: const TextStyle(color: SaturdayColors.success)),
        ],
      ),
    );
  }
}

String _fmt(DateTime d) => DateFormat('M/d HH:mm').format(d);
