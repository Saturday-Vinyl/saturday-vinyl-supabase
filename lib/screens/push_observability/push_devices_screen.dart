import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/push_observability.dart';
import 'package:saturday_app/providers/push_observability_provider.dart';
import 'package:saturday_app/screens/push_observability/push_activity_log_screen.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/push_observability/send_test_push_dialog.dart';

/// Devices table backed by admin_push_devices.
///
/// Sorted by failed_7d desc so unhealthy tokens float to the top. Tapping a
/// row opens the activity log pre-filtered to that token.
class PushDevicesScreen extends ConsumerStatefulWidget {
  const PushDevicesScreen({super.key});

  @override
  ConsumerState<PushDevicesScreen> createState() => _PushDevicesScreenState();
}

class _PushDevicesScreenState extends ConsumerState<PushDevicesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(pushDeviceFilterProvider);
    final devicesAsync = ref.watch(pushDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(pushDevicesProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(filter),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(pushDevicesProvider),
              child: devicesAsync.when(
                loading: () => const LoadingIndicator(),
                error: (error, _) => ErrorState(
                  message: 'Failed to load devices',
                  details: error.toString(),
                  onRetry: () => ref.invalidate(pushDevicesProvider),
                ),
                data: (devices) {
                  if (devices.isEmpty) {
                    return const EmptyState(
                      icon: Icons.phone_iphone,
                      message: 'No push devices match the current filters',
                    );
                  }
                  return _DevicesTable(devices: devices);
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
      child: Row(
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
                              .read(pushDeviceFilterProvider.notifier)
                              .setSearch(null);
                        },
                      )
                    : null,
              ),
              onChanged: (v) =>
                  ref.read(pushDeviceFilterProvider.notifier).setSearch(v),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: filter.platform,
            hint: const Text('Platform'),
            items: const [
              DropdownMenuItem(value: null, child: Text('All platforms')),
              DropdownMenuItem(value: 'ios', child: Text('iOS')),
              DropdownMenuItem(value: 'android', child: Text('Android')),
            ],
            onChanged: (v) =>
                ref.read(pushDeviceFilterProvider.notifier).setPlatform(v),
          ),
          const SizedBox(width: 12),
          DropdownButton<bool?>(
            value: filter.isActive,
            hint: const Text('Active'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Any')),
              DropdownMenuItem(value: true, child: Text('Active only')),
              DropdownMenuItem(value: false, child: Text('Inactive only')),
            ],
            onChanged: (v) =>
                ref.read(pushDeviceFilterProvider.notifier).setIsActive(v),
          ),
        ],
      ),
    );
  }
}

class _DevicesTable extends ConsumerWidget {
  final List<PushDevice> devices;
  const _DevicesTable({required this.devices});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
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
              columnSpacing: 24,
              showCheckboxColumn: false,
              columns: const [
                DataColumn(label: Text('USER')),
                DataColumn(label: Text('PLATFORM')),
                DataColumn(label: Text('APP VERSION')),
                DataColumn(label: Text('ACTIVE')),
                DataColumn(label: Text('SENT 7D'), numeric: true),
                DataColumn(label: Text('FAILED 7D'), numeric: true),
                DataColumn(label: Text('LAST USED')),
                DataColumn(label: Text('LAST SENT')),
                DataColumn(label: Text('LAST FAILED')),
                DataColumn(label: Text('')),
              ],
              rows: devices.map((d) => _buildRow(context, ref, d)).toList(),
            ),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, WidgetRef ref, PushDevice d) {
    return DataRow(
      color: d.likelyDead
          ? WidgetStateProperty.all(
              SaturdayColors.error.withValues(alpha: 0.07))
          : null,
      onSelectChanged: (_) => _openActivity(context, ref, d),
      cells: [
        DataCell(
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(d.displayName ?? d.email ?? d.userId,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (d.email != null && d.displayName != null)
                  Text(
                    d.email!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SaturdayColors.secondaryGrey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
        DataCell(Text(d.platform,
            style: const TextStyle(fontFamily: 'monospace'))),
        DataCell(Text(d.appVersion ?? '—')),
        DataCell(d.isActive
            ? const Icon(Icons.check_circle,
                color: SaturdayColors.success, size: 16)
            : const Icon(Icons.cancel,
                color: SaturdayColors.secondaryGrey, size: 16)),
        DataCell(Text(d.sent7d.toString())),
        DataCell(Text(
          d.failed7d.toString(),
          style: TextStyle(
            fontWeight: d.failed7d > 0 ? FontWeight.w700 : FontWeight.normal,
            color: d.failed7d > 0
                ? SaturdayColors.error
                : SaturdayColors.primaryDark,
          ),
        )),
        DataCell(Text(_fmt(d.lastUsedAt))),
        DataCell(Text(_fmt(d.lastSentAt))),
        DataCell(Text(_fmt(d.lastFailedAt))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.send, size: 18),
              tooltip: d.isActive
                  ? 'Send test push'
                  : 'Token is inactive — reactivate first',
              onPressed: d.isActive
                  ? () => SendTestPushDialog.show(context, d)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 18),
              tooltip: 'View deliveries',
              onPressed: () => _openActivity(context, ref, d),
            ),
          ],
        )),
      ],
    );
  }

  void _openActivity(BuildContext context, WidgetRef ref, PushDevice d) {
    ref.read(pushDeliveryFilterProvider.notifier).setTokenId(d.tokenId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PushActivityLogScreen(),
      ),
    );
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('M/d HH:mm').format(d);
  }
}
