import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/order.dart';

/// Widget for selecting an order (or choosing no order for inventory build)
class OrderSelector extends StatelessWidget {
  final List<Order> orders;
  final Order? selectedOrder;
  final bool buildForInventory;
  final ValueChanged<Order?> onOrderSelected;
  final VoidCallback onBuildForInventory;

  const OrderSelector({
    super.key,
    required this.orders,
    this.selectedOrder,
    required this.buildForInventory,
    required this.onOrderSelected,
    required this.onBuildForInventory,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // "Build for Inventory" option
        Card(
          elevation: buildForInventory ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: buildForInventory
                  ? SaturdayColors.info
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: onBuildForInventory,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: buildForInventory
                            ? SaturdayColors.info
                            : SaturdayColors.secondaryGrey,
                        width: 2,
                      ),
                      color: buildForInventory
                          ? SaturdayColors.info
                          : Colors.transparent,
                    ),
                    child: buildForInventory
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Build for Inventory (No Order)',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: buildForInventory
                                        ? SaturdayColors.info
                                        : SaturdayColors.primaryDark,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This unit will be added to inventory',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: SaturdayColors.secondaryGrey,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.inventory_2_outlined,
                    color: buildForInventory
                        ? SaturdayColors.info
                        : SaturdayColors.secondaryGrey,
                    size: 32,
                  ),
                ],
              ),
            ),
          ),
        ),

        if (orders.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Or select an order:',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
          const SizedBox(height: 12),

          // List of orders
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final isSelected =
                  !buildForInventory && selectedOrder?.id == order.id;

              return _OrderCard(
                order: order,
                isSelected: isSelected,
                onTap: () => onOrderSelected(order),
              );
            },
          ),
        ] else if (!buildForInventory) ...[
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 48,
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'No matching orders found',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Build for inventory or sync orders from Shopify',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final bool isSelected;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? SaturdayColors.success : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? SaturdayColors.success
                        : SaturdayColors.secondaryGrey,
                    width: 2,
                  ),
                  color:
                      isSelected ? SaturdayColors.success : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ${order.shopifyOrderNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? SaturdayColors.success
                                : SaturdayColors.primaryDark,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.orderDate.toString().split(' ')[0],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
