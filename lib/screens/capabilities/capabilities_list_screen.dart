import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/providers/capability_provider.dart';
import 'package:saturday_app/screens/capabilities/capability_form_screen.dart';

/// Screen for managing device capabilities
class CapabilitiesListScreen extends ConsumerWidget {
  const CapabilitiesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilitiesAsync = ref.watch(allCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capabilities'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _navigateToForm(context, ref),
            tooltip: 'Add Capability',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allCapabilitiesProvider),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: capabilitiesAsync.when(
        data: (capabilities) {
          if (capabilities.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.extension_off,
                    size: 64,
                    color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No capabilities defined',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Capabilities define what features a device type supports',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SaturdayColors.secondaryGrey,
                        ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(allCapabilitiesProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: capabilities.length,
              itemBuilder: (context, index) {
                final capability = capabilities[index];
                return _CapabilityCard(
                  capability: capability,
                  onEdit: () => _navigateToForm(context, ref, capability: capability),
                  onDelete: () => _confirmDelete(context, ref, capability),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: SaturdayColors.error),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(allCapabilitiesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToForm(BuildContext context, WidgetRef ref, {Capability? capability}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CapabilityFormScreen(capability: capability),
      ),
    );

    if (result == true) {
      ref.invalidate(allCapabilitiesProvider);
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Capability capability) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Capability'),
        content: Text(
          'Are you sure you want to delete "${capability.displayName}"?\n\n'
          'This action cannot be undone and may affect device types using this capability.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(capabilityManagementProvider).deleteCapability(capability.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Deleted "${capability.displayName}"'),
                      backgroundColor: SaturdayColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete: $e'),
                      backgroundColor: SaturdayColors.error,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: SaturdayColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  final Capability capability;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CapabilityCard({
    required this.capability,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showCapabilityDetails(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: SaturdayColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.extension,
                      color: SaturdayColors.info,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          capability.displayName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          capability.name,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SaturdayColors.secondaryGrey,
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit?.call();
                      } else if (value == 'delete') {
                        onDelete?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: SaturdayColors.error),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(color: SaturdayColors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (capability.description != null) ...[
                const SizedBox(height: 12),
                Text(
                  capability.description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip(
                    Icons.factory,
                    '${_countSchemaFields(capability.factoryInputSchema)} factory fields',
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.person,
                    '${_countSchemaFields(capability.consumerInputSchema)} consumer fields',
                  ),
                  const SizedBox(width: 8),
                  if (capability.tests.isNotEmpty)
                    _buildInfoChip(
                      Icons.science,
                      '${capability.tests.length} tests',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    final isActive = capability.isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? SaturdayColors.success : SaturdayColors.secondaryGrey)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? SaturdayColors.success : SaturdayColors.secondaryGrey,
        ),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: isActive ? SaturdayColors.success : SaturdayColors.secondaryGrey,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: SaturdayColors.secondaryGrey),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: SaturdayColors.secondaryGrey,
          ),
        ),
      ],
    );
  }

  int _countSchemaFields(Map<String, dynamic>? schema) {
    if (schema == null) return 0;
    final properties = schema['properties'] as Map<String, dynamic>?;
    return properties?.length ?? 0;
  }

  void _showCapabilityDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CapabilityDetailSheet(
          capability: capability,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _CapabilityDetailSheet extends StatelessWidget {
  final Capability capability;
  final ScrollController scrollController;

  const _CapabilityDetailSheet({
    required this.capability,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: SaturdayColors.secondaryGrey,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                capability.displayName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                capability.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              if (capability.description != null) ...[
                const SizedBox(height: 16),
                Text(capability.description!),
              ],
              const SizedBox(height: 24),
              _buildSection(
                context,
                'Factory Input Schema',
                'Data sent to device during factory provisioning (UART/WebSocket)',
                capability.factoryInputSchema,
              ),
              const SizedBox(height: 16),
              _buildSection(
                context,
                'Factory Output Schema',
                'Data returned by device after factory provisioning',
                capability.factoryOutputSchema,
              ),
              const SizedBox(height: 16),
              _buildSection(
                context,
                'Consumer Input Schema',
                'Data sent to device during consumer provisioning (BLE)',
                capability.consumerInputSchema,
              ),
              const SizedBox(height: 16),
              _buildSection(
                context,
                'Consumer Output Schema',
                'Data returned by device after consumer provisioning',
                capability.consumerOutputSchema,
              ),
              const SizedBox(height: 16),
              _buildSection(
                context,
                'Heartbeat Schema',
                'Telemetry data from device heartbeats',
                capability.heartbeatSchema,
              ),
              if (capability.tests.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Tests',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                ...capability.tests.map((test) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.science,
                          color: SaturdayColors.info,
                        ),
                        title: Text(test.displayName),
                        subtitle: Text(test.description ?? test.name),
                      ),
                    )),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    String subtitle,
    Map<String, dynamic>? schema,
  ) {
    final properties = schema?['properties'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
        const SizedBox(height: 8),
        if (properties == null || properties.isEmpty)
          Text(
            'No fields defined',
            style: TextStyle(
              color: SaturdayColors.secondaryGrey,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          ...properties.entries.map((entry) {
            final fieldSchema = entry.value as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                dense: true,
                title: Text(entry.key),
                subtitle: Text(fieldSchema['type']?.toString() ?? 'unknown'),
                trailing: Text(
                  fieldSchema['description']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: SaturdayColors.secondaryGrey,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
