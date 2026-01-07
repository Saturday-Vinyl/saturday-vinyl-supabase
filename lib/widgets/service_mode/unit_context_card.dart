import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_unit.dart';

/// Card displaying the associated production unit context
class UnitContextCard extends StatelessWidget {
  final ProductionUnit? unit;
  final bool isFreshDevice;
  final VoidCallback? onSelectUnit;
  final VoidCallback? onClearUnit;

  const UnitContextCard({
    super.key,
    this.unit,
    this.isFreshDevice = false,
    this.onSelectUnit,
    this.onClearUnit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Production Unit',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (unit != null && onClearUnit != null)
                  IconButton(
                    onPressed: onClearUnit,
                    icon: const Icon(Icons.clear, size: 20),
                    tooltip: 'Clear unit selection',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (unit != null) ...[
              _buildUnitInfo(context, unit!),
            ] else if (isFreshDevice) ...[
              _buildSelectUnitPrompt(context),
            ] else ...[
              _buildNoUnitMessage(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUnitInfo(BuildContext context, ProductionUnit unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Unit ID
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SaturdayColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                unit.unitId,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
            const Spacer(),
            if (unit.isCompleted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SaturdayColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'COMPLETED',
                  style: TextStyle(
                    color: SaturdayColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SaturdayColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'IN PRODUCTION',
                  style: TextStyle(
                    color: SaturdayColors.info,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // MAC address if available
        if (unit.macAddress != null && unit.macAddress!.isNotEmpty) ...[
          _buildInfoRow('MAC Address', unit.macAddress!, Icons.router),
          const SizedBox(height: 4),
        ],

        // Customer info if available
        if (unit.customerName != null && unit.customerName!.isNotEmpty) ...[
          _buildInfoRow('Customer', unit.customerName!, Icons.person),
          const SizedBox(height: 4),
        ],

        // Order info if available
        if (unit.shopifyOrderNumber != null) ...[
          _buildInfoRow('Order', unit.shopifyOrderNumber!, Icons.receipt),
          const SizedBox(height: 4),
        ],

        // Created date
        _buildInfoRow(
          'Created',
          _formatDate(unit.createdAt),
          Icons.calendar_today,
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectUnitPrompt(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.add_circle_outline,
          size: 48,
          color: Colors.grey[400],
        ),
        const SizedBox(height: 12),
        Text(
          'Fresh device detected',
          style: TextStyle(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Select a production unit to associate with this device',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (onSelectUnit != null)
          ElevatedButton.icon(
            onPressed: onSelectUnit,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Select Unit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.info,
              foregroundColor: Colors.white,
            ),
          ),
      ],
    );
  }

  Widget _buildNoUnitMessage(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.info_outline,
          size: 36,
          color: Colors.grey[400],
        ),
        const SizedBox(height: 8),
        Text(
          'No unit associated',
          style: TextStyle(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Connect to a device to see unit information',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
