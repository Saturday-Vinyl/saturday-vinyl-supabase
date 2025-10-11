import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/utils/extensions.dart';

/// Card widget for displaying product in list view
class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Product icon placeholder
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: SaturdayColors.light,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 32,
                  color: SaturdayColors.primaryDark,
                ),
              ),
              const SizedBox(width: 16),
              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: SaturdayColors.primaryDark,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.productCode,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                    if (product.lastSyncedAt != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.sync,
                            size: 14,
                            color: SaturdayColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Synced ${product.lastSyncedAt!.timeAgo}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: SaturdayColors.secondaryGrey,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Chevron icon
              const Icon(
                Icons.chevron_right,
                color: SaturdayColors.secondaryGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
