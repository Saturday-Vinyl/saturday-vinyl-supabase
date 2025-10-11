import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/providers/product_provider.dart';

/// Dialog for creating or editing a product variant
class VariantFormDialog extends ConsumerStatefulWidget {
  final String productId;
  final ProductVariant? variant;

  const VariantFormDialog({
    super.key,
    required this.productId,
    this.variant,
  });

  @override
  ConsumerState<VariantFormDialog> createState() => _VariantFormDialogState();
}

class _VariantFormDialogState extends ConsumerState<VariantFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _shopifyIdController;
  late TextEditingController _skuController;
  late TextEditingController _nameController;
  late TextEditingController _option1NameController;
  late TextEditingController _option1ValueController;
  late TextEditingController _option2NameController;
  late TextEditingController _option2ValueController;
  late TextEditingController _option3NameController;
  late TextEditingController _option3ValueController;
  late TextEditingController _priceController;
  late bool _isActive;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final variant = widget.variant;

    _shopifyIdController = TextEditingController(text: variant?.shopifyVariantId ?? '');
    _skuController = TextEditingController(text: variant?.sku ?? '');
    _nameController = TextEditingController(text: variant?.name ?? '');
    _option1NameController = TextEditingController(text: variant?.option1Name ?? '');
    _option1ValueController = TextEditingController(text: variant?.option1Value ?? '');
    _option2NameController = TextEditingController(text: variant?.option2Name ?? '');
    _option2ValueController = TextEditingController(text: variant?.option2Value ?? '');
    _option3NameController = TextEditingController(text: variant?.option3Name ?? '');
    _option3ValueController = TextEditingController(text: variant?.option3Value ?? '');
    _priceController = TextEditingController(text: variant?.price.toStringAsFixed(2) ?? '0.00');
    _isActive = variant?.isActive ?? true;
  }

  @override
  void dispose() {
    _shopifyIdController.dispose();
    _skuController.dispose();
    _nameController.dispose();
    _option1NameController.dispose();
    _option1ValueController.dispose();
    _option2NameController.dispose();
    _option2ValueController.dispose();
    _option3NameController.dispose();
    _option3ValueController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.variant != null;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: SaturdayColors.primaryDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.add_circle,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Variant' : 'Add New Variant',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shopify Variant ID
                      TextFormField(
                        controller: _shopifyIdController,
                        decoration: const InputDecoration(
                          labelText: 'Shopify Variant ID',
                          hintText: 'gid://shopify/ProductVariant/...',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter Shopify variant ID';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // SKU
                      TextFormField(
                        controller: _skuController,
                        decoration: const InputDecoration(
                          labelText: 'SKU',
                          hintText: 'SV-WALNUT-001',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter SKU';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Variant Name',
                          hintText: 'Walnut / Black Liner',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter variant name';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // Price
                      TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          hintText: '199.99',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter price';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter valid price';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 24),

                      // Options Section
                      Text(
                        'Product Options',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),

                      // Option 1
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _option1NameController,
                              decoration: const InputDecoration(
                                labelText: 'Option 1 Name',
                                hintText: 'Wood Species',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _option1ValueController,
                              decoration: const InputDecoration(
                                labelText: 'Option 1 Value',
                                hintText: 'Walnut',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Option 2
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _option2NameController,
                              decoration: const InputDecoration(
                                labelText: 'Option 2 Name',
                                hintText: 'Liner Color',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _option2ValueController,
                              decoration: const InputDecoration(
                                labelText: 'Option 2 Value',
                                hintText: 'Black',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Option 3
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _option3NameController,
                              decoration: const InputDecoration(
                                labelText: 'Option 3 Name',
                                hintText: 'Size',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _option3ValueController,
                              decoration: const InputDecoration(
                                labelText: 'Option 3 Value',
                                hintText: 'Large',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Active checkbox
                      if (isEditing)
                        SwitchListTile(
                          title: const Text('Active'),
                          subtitle: const Text('Variant is available for production'),
                          value: _isActive,
                          onChanged: (value) {
                            setState(() {
                              _isActive = value;
                            });
                          },
                        ),

                      // Delete button for editing
                      if (isEditing) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _deleteVariant,
                          icon: const Icon(Icons.delete),
                          label: const Text('Delete Variant'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SaturdayColors.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveVariant,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.success,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isEditing ? 'Update' : 'Create'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveVariant() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final management = ref.read(variantManagementProvider);
      final price = double.parse(_priceController.text);

      if (widget.variant != null) {
        // Update existing variant
        await management.updateVariant(
          variantId: widget.variant!.id,
          productId: widget.productId,
          sku: _skuController.text.trim(),
          name: _nameController.text.trim(),
          option1Name: _option1NameController.text.trim().isEmpty ? null : _option1NameController.text.trim(),
          option1Value: _option1ValueController.text.trim().isEmpty ? null : _option1ValueController.text.trim(),
          option2Name: _option2NameController.text.trim().isEmpty ? null : _option2NameController.text.trim(),
          option2Value: _option2ValueController.text.trim().isEmpty ? null : _option2ValueController.text.trim(),
          option3Name: _option3NameController.text.trim().isEmpty ? null : _option3NameController.text.trim(),
          option3Value: _option3ValueController.text.trim().isEmpty ? null : _option3ValueController.text.trim(),
          price: price,
          isActive: _isActive,
        );
      } else {
        // Create new variant
        await management.createVariant(
          productId: widget.productId,
          shopifyVariantId: _shopifyIdController.text.trim(),
          sku: _skuController.text.trim(),
          name: _nameController.text.trim(),
          option1Name: _option1NameController.text.trim().isEmpty ? null : _option1NameController.text.trim(),
          option1Value: _option1ValueController.text.trim().isEmpty ? null : _option1ValueController.text.trim(),
          option2Name: _option2NameController.text.trim().isEmpty ? null : _option2NameController.text.trim(),
          option2Value: _option2ValueController.text.trim().isEmpty ? null : _option2ValueController.text.trim(),
          option3Name: _option3NameController.text.trim().isEmpty ? null : _option3NameController.text.trim(),
          option3Value: _option3ValueController.text.trim().isEmpty ? null : _option3ValueController.text.trim(),
          price: price,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteVariant() async {
    if (widget.variant == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Variant'),
        content: const Text('Are you sure you want to delete this variant? This will soft-delete it (set as inactive).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final management = ref.read(variantManagementProvider);
      await management.deleteVariant(widget.variant!.id, widget.productId);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting variant: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
