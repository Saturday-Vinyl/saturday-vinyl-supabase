import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product_variant.dart';

/// Widget for selecting a product variant from a list
class VariantSelector extends StatelessWidget {
  final List<ProductVariant> variants;
  final ProductVariant? selectedVariant;
  final ValueChanged<ProductVariant> onVariantSelected;

  const VariantSelector({
    super.key,
    required this.variants,
    this.selectedVariant,
    required this.onVariantSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: variants.length,
      itemBuilder: (context, index) {
        final variant = variants[index];
        final isSelected = selectedVariant?.id == variant.id;

        return _VariantCard(
          variant: variant,
          isSelected: isSelected,
          onTap: () => onVariantSelected(variant),
        );
      },
    );
  }
}

class _VariantCard extends StatelessWidget {
  final ProductVariant variant;
  final bool isSelected;
  final VoidCallback onTap;

  const _VariantCard({
    required this.variant,
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
              // Radio button indicator
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
                  color: isSelected ? SaturdayColors.success : Colors.transparent,
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

              // Variant details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.getFormattedVariantName(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? SaturdayColors.success
                                : SaturdayColors.primaryDark,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SKU: ${variant.sku}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                    if (variant.option1Value != null ||
                        variant.option2Value != null ||
                        variant.option3Value != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (variant.option1Value != null)
                            _OptionChip(
                              label: variant.option1Name ?? 'Option 1',
                              value: variant.option1Value!,
                            ),
                          if (variant.option2Value != null)
                            _OptionChip(
                              label: variant.option2Name ?? 'Option 2',
                              value: variant.option2Value!,
                            ),
                          if (variant.option3Value != null)
                            _OptionChip(
                              label: variant.option3Name ?? 'Option 3',
                              value: variant.option3Value!,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Price
              const SizedBox(width: 16),
              Text(
                '\$${variant.price.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: SaturdayColors.primaryDark,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final String value;

  const _OptionChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SaturdayColors.light,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 11,
            ),
      ),
    );
  }
}
