import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/order.dart';
import 'package:intl/intl.dart';

/// Widget displaying an order summary card
class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  final VoidCallback? onBuildUnit;
  final bool showBuildButton;

  const OrderCard({
    super.key,
    required this.order,
    this.onTap,
    this.onBuildUnit,
    this.showBuildButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order header
              Row(
                children: [
                  // Order number
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: SaturdayColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Order #${order.shopifyOrderNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: SaturdayColors.info,
                          ),
                    ),
                  ),
                  const Spacer(),
                  // Order date
                  Text(
                    _formatDate(order.orderDate),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondaryGrey,
                        ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Customer info
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 18,
                    color: SaturdayColors.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),

              if (order.customer?.email != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 16,
                      color: SaturdayColors.secondaryGrey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      order.customer!.email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ),
              ],

              if (order.lineItems.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                // Line items
                Text(
                  'Items:',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                ...order.lineItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: SaturdayColors.light,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${item.quantity}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: SaturdayColors.primaryDark,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item.variantOptions != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.variantOptions!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: SaturdayColors.secondaryGrey,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (item.price != null)
                          Text(
                            item.price!,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],

              // Order total and status
              if (order.totalPrice != null || order.financialStatus != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (order.financialStatus != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(order.financialStatus!).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          order.financialStatus!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _getStatusColor(order.financialStatus!),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (order.totalPrice != null)
                      Text(
                        'Total: ${order.totalPrice}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],

              // Build unit button
              if (showBuildButton && onBuildUnit != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onBuildUnit,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Build Unit for This Order'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.success,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return SaturdayColors.success;
      case 'PENDING':
      case 'AUTHORIZED':
        return SaturdayColors.info;
      case 'REFUNDED':
      case 'VOIDED':
        return SaturdayColors.secondaryGrey;
      case 'UNPAID':
      case 'PARTIALLY_PAID':
        return SaturdayColors.error;
      default:
        return SaturdayColors.primaryDark;
    }
  }
}
