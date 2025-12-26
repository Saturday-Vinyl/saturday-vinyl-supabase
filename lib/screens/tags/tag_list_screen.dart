import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/tag_filter.dart';
import 'package:saturday_app/providers/bulk_write_provider.dart';
import 'package:saturday_app/providers/rfid_tag_provider.dart';
import 'package:saturday_app/screens/tags/tag_detail_screen.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/providers/scan_mode_provider.dart';
import 'package:saturday_app/widgets/tags/activity_log.dart';
import 'package:saturday_app/widgets/tags/bulk_write_status.dart';
import 'package:saturday_app/widgets/tags/rfid_module_status.dart';
import 'package:saturday_app/widgets/tags/scan_mode_indicator.dart';
import 'package:saturday_app/widgets/tags/tag_list_item.dart';

/// Main screen for viewing and managing RFID tags
class TagListScreen extends ConsumerStatefulWidget {
  const TagListScreen({super.key});

  @override
  ConsumerState<TagListScreen> createState() => _TagListScreenState();
}

class _TagListScreenState extends ConsumerState<TagListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(tagFilterProvider);
    final tagsAsync = ref.watch(filteredRfidTagsProvider);
    final scanState = ref.watch(scanModeProvider);
    final bulkState = ref.watch(bulkWriteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags'),
        actions: const [
          RfidAppBarStatus(),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          _buildFilterBar(filter, scanState.isScanning, bulkState.isWriting),

          // Bulk write status indicator (when writing)
          const BulkWriteStatus(),

          // Scan mode indicator (when scanning)
          const ScanModeIndicator(),

          // Tag list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshTags,
              child: tagsAsync.when(
                data: (tags) => _buildTagList(tags, scanState),
                loading: () => const LoadingIndicator(),
                error: (error, _) => ErrorState(
                  message: 'Failed to load tags',
                  details: error.toString(),
                  onRetry: _refreshTags,
                ),
              ),
            ),
          ),

          // Activity log at bottom
          const ActivityLog(initiallyExpanded: false),
        ],
      ),
    );
  }

  Widget _buildFilterBar(TagFilter filter, bool isScanning, bool isWriting) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by EPC...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clearSearch,
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onChanged: _onSearchChanged,
          ),

          const SizedBox(height: 12),

          // Filter row
          Row(
            children: [
              // Status filter
              Expanded(
                child: _buildStatusDropdown(filter),
              ),

              const SizedBox(width: 12),

              // Sort dropdown
              Expanded(
                child: _buildSortDropdown(filter),
              ),

              const SizedBox(width: 12),

              // Add button - toggles between Add and Stop when writing
              isWriting
                  ? FilledButton.icon(
                      onPressed: _onStopBulkWrite,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SaturdayColors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: isScanning ? null : _onAddTag,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SaturdayColors.primaryDark,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),

              const SizedBox(width: 8),

              // Scan button (changes appearance when scanning)
              isScanning
                  ? FilledButton.icon(
                      onPressed: _onStopScan,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SaturdayColors.error,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: isWriting ? null : _onScan,
                      icon: const Icon(Icons.sensors, size: 18),
                      label: const Text('Scan'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown(TagFilter filter) {
    return DropdownButtonFormField<RfidTagStatus?>(
      value: filter.status,
      decoration: const InputDecoration(
        labelText: 'Status',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        const DropdownMenuItem<RfidTagStatus?>(
          value: null,
          child: Text('All Statuses'),
        ),
        ...RfidTagStatus.values.map((status) => DropdownMenuItem(
              value: status,
              child: Text(_getStatusLabel(status)),
            )),
      ],
      onChanged: (value) {
        ref.read(tagFilterProvider.notifier).setStatus(value);
      },
    );
  }

  Widget _buildSortDropdown(TagFilter filter) {
    return DropdownButtonFormField<String>(
      value: '${filter.sortBy.name}_${filter.sortAscending ? 'asc' : 'desc'}',
      decoration: const InputDecoration(
        labelText: 'Sort By',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(
          value: 'createdAt_desc',
          child: Text('Newest First'),
        ),
        DropdownMenuItem(
          value: 'createdAt_asc',
          child: Text('Oldest First'),
        ),
        DropdownMenuItem(
          value: 'epcIdentifier_asc',
          child: Text('EPC A-Z'),
        ),
        DropdownMenuItem(
          value: 'epcIdentifier_desc',
          child: Text('EPC Z-A'),
        ),
        DropdownMenuItem(
          value: 'status_asc',
          child: Text('Status'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        final parts = value.split('_');
        final sortBy = TagSortBy.values.firstWhere((e) => e.name == parts[0]);
        final ascending = parts[1] == 'asc';
        ref.read(tagFilterProvider.notifier).setSortBy(sortBy);
        ref.read(tagFilterProvider.notifier).setSortAscending(ascending);
      },
    );
  }

  Widget _buildTagList(List<RfidTag> tags, ScanModeState scanState) {
    if (tags.isEmpty) {
      final filter = ref.read(tagFilterProvider);
      if (filter.hasActiveFilters) {
        return EmptyState(
          icon: Icons.search_off,
          message: 'No tags match your current filters.\nTry adjusting your search or status filter.',
          actionLabel: 'Clear Filters',
          onAction: _clearFilters,
        );
      }
      return const EmptyState(
        icon: Icons.label_off,
        message: 'No tags yet.\nGet started by creating your first RFID tag or scanning existing tags.',
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tags.length,
      itemBuilder: (context, index) {
        final tag = tags[index];
        final isHighlighted = scanState.foundEpcs.contains(tag.epcIdentifier);
        return TagListItem(
          tag: tag,
          onTap: () => _openTagDetail(tag),
          isHighlighted: isHighlighted,
        );
      },
    );
  }

  String _getStatusLabel(RfidTagStatus status) {
    switch (status) {
      case RfidTagStatus.generated:
        return 'Generated';
      case RfidTagStatus.written:
        return 'Written';
      case RfidTagStatus.locked:
        return 'Locked';
      case RfidTagStatus.failed:
        return 'Failed';
      case RfidTagStatus.retired:
        return 'Retired';
    }
  }

  void _onSearchChanged(String query) {
    ref.read(tagFilterProvider.notifier).setSearchQuery(
          query.isEmpty ? null : query,
        );
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(tagFilterProvider.notifier).setSearchQuery(null);
  }

  void _clearFilters() {
    _searchController.clear();
    ref.read(tagFilterProvider.notifier).reset();
  }

  Future<void> _refreshTags() async {
    ref.invalidate(filteredRfidTagsProvider);
  }

  void _openTagDetail(RfidTag tag) {
    TagDetailScreen.show(context, tag.id);
  }

  Future<void> _onAddTag() async {
    final bulkNotifier = ref.read(bulkWriteProvider.notifier);
    final success = await bulkNotifier.startBulkWrite();

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(bulkWriteProvider).lastError ?? 'Failed to start bulk write',
          ),
          backgroundColor: SaturdayColors.error,
        ),
      );
    }
  }

  void _onStopBulkWrite() {
    ref.read(bulkWriteProvider.notifier).stopBulkWrite();
  }

  Future<void> _onScan() async {
    final scanNotifier = ref.read(scanModeProvider.notifier);
    final success = await scanNotifier.startScanning();

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(scanModeProvider).lastError ?? 'Failed to start scanning',
          ),
          backgroundColor: SaturdayColors.error,
        ),
      );
    }
  }

  Future<void> _onStopScan() async {
    final scanNotifier = ref.read(scanModeProvider.notifier);
    await scanNotifier.stopScanning();
  }
}
