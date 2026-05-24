import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/push_observability.dart';
import 'package:saturday_app/providers/push_observability_provider.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/push_observability/push_activity_row.dart';

/// Full activity log with filter chips. Backed by admin_push_deliveries.
class PushActivityLogScreen extends ConsumerStatefulWidget {
  const PushActivityLogScreen({super.key});

  @override
  ConsumerState<PushActivityLogScreen> createState() =>
      _PushActivityLogScreenState();
}

class _PushActivityLogScreenState extends ConsumerState<PushActivityLogScreen> {
  static const List<String> _knownTypes = [
    'now_playing',
    'device_offline',
    'device_online',
    'low_battery',
    'admin_test',
  ];

  static const List<_WindowOption> _windows = [
    _WindowOption('1h', Duration(hours: 1)),
    _WindowOption('24h', Duration(hours: 24)),
    _WindowOption('7d', Duration(days: 7)),
  ];

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = ref.read(pushDeliveryFilterProvider).searchEmail;
    if (initial != null) _searchController.text = initial;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(pushDeliveryFilterProvider);
    final feedAsync = ref.watch(pushDeliveriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Activity'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: 'Reset filters',
            onPressed: () {
              _searchController.clear();
              ref.read(pushDeliveryFilterProvider.notifier).reset();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(pushDeliveriesProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(filter),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(pushDeliveriesProvider),
              child: feedAsync.when(
                loading: () => const LoadingIndicator(),
                error: (error, _) => ErrorState(
                  message: 'Failed to load activity',
                  details: error.toString(),
                  onRetry: () => ref.invalidate(pushDeliveriesProvider),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const EmptyState(
                      icon: Icons.inbox_outlined,
                      message:
                          'No delivery attempts match the current filters',
                    );
                  }
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) =>
                        PushActivityRow(delivery: rows[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(filter) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by email or name…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(pushDeliveryFilterProvider.notifier)
                                  .setSearch(null);
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => ref
                      .read(pushDeliveryFilterProvider.notifier)
                      .setSearch(v),
                ),
              ),
              if (filter.tokenId != null) ...[
                const SizedBox(width: 12),
                Chip(
                  label: const Text('Filtered by token'),
                  onDeleted: () => ref
                      .read(pushDeliveryFilterProvider.notifier)
                      .setTokenId(null),
                  backgroundColor:
                      SaturdayColors.info.withValues(alpha: 0.15),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _typeChip(null, 'All types', filter.notificationType == null),
              for (final t in _knownTypes)
                _typeChip(t, t, filter.notificationType == t),
              const _Divider(),
              _statusChip(null, 'All', filter.status == null),
              _statusChip(
                  PushDeliveryStatus.sent, 'Sent',
                  filter.status == PushDeliveryStatus.sent),
              _statusChip(
                  PushDeliveryStatus.failed, 'Failed',
                  filter.status == PushDeliveryStatus.failed),
              _statusChip(
                  PushDeliveryStatus.pending, 'Pending',
                  filter.status == PushDeliveryStatus.pending),
              const _Divider(),
              for (final w in _windows)
                ChoiceChip(
                  label: Text(w.label),
                  selected: filter.window == w.window,
                  onSelected: (_) => ref
                      .read(pushDeliveryFilterProvider.notifier)
                      .setWindow(w.window),
                  selectedColor:
                      SaturdayColors.primaryDark.withValues(alpha: 0.15),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String? type, String label, bool selected) {
    return ChoiceChip(
      label: Text(
        label,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
      selected: selected,
      onSelected: (_) => ref
          .read(pushDeliveryFilterProvider.notifier)
          .setNotificationType(selected ? null : type),
      selectedColor: SaturdayColors.primaryDark.withValues(alpha: 0.15),
    );
  }

  Widget _statusChip(PushDeliveryStatus? status, String label, bool selected) {
    final color = status == PushDeliveryStatus.failed
        ? SaturdayColors.error
        : status == PushDeliveryStatus.sent
            ? SaturdayColors.success
            : SaturdayColors.primaryDark;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) => ref
          .read(pushDeliveryFilterProvider.notifier)
          .setStatus(selected ? null : status),
      selectedColor: color.withValues(alpha: 0.15),
    );
  }
}

class _WindowOption {
  final String label;
  final Duration window;
  const _WindowOption(this.label, this.window);
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
