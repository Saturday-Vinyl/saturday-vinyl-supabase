import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/order.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/order_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/providers/production_unit_provider.dart';
import 'package:saturday_app/providers/settings_provider.dart';
import 'package:saturday_app/services/printer_service.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/production/order_selector.dart';
import 'package:saturday_app/widgets/production/print_preview_dialog.dart';
import 'package:saturday_app/widgets/production/product_selector.dart';
import 'package:saturday_app/widgets/production/qr_code_display.dart';
import 'package:saturday_app/widgets/production/variant_selector.dart';

/// Multi-step wizard for creating a production unit
class CreateUnitScreen extends ConsumerStatefulWidget {
  const CreateUnitScreen({super.key});

  @override
  ConsumerState<CreateUnitScreen> createState() => _CreateUnitScreenState();
}

class _CreateUnitScreenState extends ConsumerState<CreateUnitScreen> {
  int _currentStep = 0;
  Product? _selectedProduct;
  ProductVariant? _selectedVariant;
  Order? _selectedOrder;
  bool _buildForInventory = true;
  ProductionUnit? _createdUnit;
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Production Unit'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: SaturdayColors.success,
            onPrimary: Colors.white,
          ),
        ),
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: _onStepContinue,
          onStepCancel: _onStepCancel,
          onStepTapped: (step) {
            if (step < _currentStep) {
              setState(() {
                _currentStep = step;
              });
            }
          },
          controlsBuilder: (context, details) {
            final isLastStep = _currentStep == 3;
            final canContinue = _canContinueFromCurrentStep();

            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  if (!isLastStep && _createdUnit == null)
                    ElevatedButton(
                      onPressed: canContinue ? details.onStepContinue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SaturdayColors.success,
                        foregroundColor: Colors.white,
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Continue'),
                    ),
                  if (_currentStep > 0 && _createdUnit == null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Back'),
                    ),
                  ],
                  if (_createdUnit != null) ...[
                    // Show print button only on desktop
                    if (Platform.isMacOS ||
                        Platform.isWindows ||
                        Platform.isLinux)
                      ElevatedButton.icon(
                        onPressed: _printLabel,
                        icon: const Icon(Icons.print),
                        label: const Text('Print Label'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SaturdayColors.primaryDark,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    if (Platform.isMacOS ||
                        Platform.isWindows ||
                        Platform.isLinux)
                      const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, _createdUnit),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SaturdayColors.success,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Done'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _resetWizard,
                      child: const Text('Create Another'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Select Product'),
              content: _buildProductStep(),
              isActive: _currentStep >= 0,
              state: _getStepState(0),
            ),
            Step(
              title: const Text('Select Variant'),
              content: _buildVariantStep(),
              isActive: _currentStep >= 1,
              state: _getStepState(1),
            ),
            Step(
              title: const Text('Associate Order (Optional)'),
              content: _buildOrderStep(),
              isActive: _currentStep >= 2,
              state: _getStepState(2),
            ),
            Step(
              title: const Text('Confirmation'),
              content: _buildConfirmationStep(),
              isActive: _currentStep >= 3,
              state: _getStepState(3),
            ),
          ],
        ),
      ),
    );
  }

  StepState _getStepState(int step) {
    if (_createdUnit != null) {
      return StepState.complete;
    }
    if (step < _currentStep) {
      return StepState.complete;
    }
    if (step == _currentStep) {
      return StepState.editing;
    }
    return StepState.indexed;
  }

  bool _canContinueFromCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _selectedProduct != null;
      case 1:
        return _selectedVariant != null;
      case 2:
        return true; // Order is optional
      case 3:
        return false; // Last step
      default:
        return false;
    }
  }

  void _onStepContinue() async {
    if (_currentStep == 2) {
      // Last step before creation - create the unit
      await _createUnit();
    } else if (_canContinueFromCurrentStep()) {
      setState(() {
        _currentStep += 1;
      });
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep -= 1;
      });
    }
  }

  Future<void> _createUnit() async {
    if (_selectedProduct == null || _selectedVariant == null) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final currentUserAsync = ref.read(currentUserProvider);
      final currentUser = currentUserAsync.value;

      if (currentUser == null) {
        throw Exception('No user logged in');
      }

      final management = ref.read(productionUnitManagementProvider);
      final unit = await management.createUnit(
        productId: _selectedProduct!.id,
        variantId: _selectedVariant!.id,
        userId: currentUser.id,
        shopifyOrderId: _selectedOrder?.shopifyOrderId,
        shopifyOrderNumber: _selectedOrder?.shopifyOrderNumber,
        customerName: _selectedOrder?.customerName,
        orderId: _selectedOrder?.id, // Link order to unit
      );

      setState(() {
        _createdUnit = unit;
        _currentStep = 3;
        _isCreating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unit ${unit.unitId} created successfully!'),
            backgroundColor: SaturdayColors.success,
          ),
        );

        // Check auto-print setting and print automatically if enabled
        _checkAndAutoPrint();
      }
    } catch (error) {
      setState(() {
        _isCreating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create unit: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  /// Check printer settings and auto-print if enabled
  Future<void> _checkAndAutoPrint() async {
    if (_createdUnit == null ||
        _selectedProduct == null ||
        _selectedVariant == null) {
      return;
    }

    // Only auto-print on desktop platforms
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return;
    }

    try {
      // Get printer settings
      final settingsAsync = ref.read(printerSettingsProvider);
      final settings = settingsAsync.value;

      // If auto-print is not enabled, skip
      if (settings == null || !settings.autoPrint) {
        AppLogger.info('Auto-print disabled, skipping automatic print');
        return;
      }

      AppLogger.info('Auto-print enabled, printing label automatically');

      // Download QR code image
      Uint8List? qrImageData;
      try {
        final response = await http.get(Uri.parse(_createdUnit!.qrCodeUrl));
        if (response.statusCode == 200) {
          qrImageData = response.bodyBytes;
        } else {
          // If download fails, generate QR code
          final qrService = QRService();
          qrImageData = await qrService.generateQRCode(
            _createdUnit!.uuid,
            size: 200,
          );
        }
      } catch (e) {
        AppLogger.error('Error loading QR code for auto-print', e);
        // Generate QR code as fallback
        final qrService = QRService();
        qrImageData = await qrService.generateQRCode(
          _createdUnit!.uuid,
          size: 200,
        );
      }

      // Generate and print label
      final printerService = PrinterService();
      final labelData = await printerService.generateQRLabel(
        unit: _createdUnit!,
        productName: _selectedProduct!.name,
        variantName: _selectedVariant!.name,
        qrImageData: qrImageData,
      );

      // Select the default printer if configured
      if (settings.hasDefaultPrinter()) {
        final printer =
            await printerService.findPrinterById(settings.defaultPrinterId!);
        if (printer != null) {
          await printerService.selectPrinter(printer);
        }
      }

      // Print the label with proper dimensions
      final success = await printerService.printQRLabel(
        labelData,
        labelWidth: 1.0,  // 1 inch labels
        labelHeight: 1.0,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Label printed automatically'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Auto-print failed. Please print manually.'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error during auto-print', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-print error: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _resetWizard() {
    setState(() {
      _currentStep = 0;
      _selectedProduct = null;
      _selectedVariant = null;
      _selectedOrder = null;
      _buildForInventory = true;
      _createdUnit = null;
    });
  }

  Widget _buildProductStep() {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        if (products.isEmpty) {
          return const Center(
            child: Text('No products available. Please sync from Shopify.'),
          );
        }

        return ProductSelector(
          products: products,
          selectedProduct: _selectedProduct,
          onProductSelected: (product) {
            setState(() {
              _selectedProduct = product;
              _selectedVariant = null; // Reset variant when product changes
            });
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildVariantStep() {
    if (_selectedProduct == null) {
      return const Text('Please select a product first');
    }

    final variantsAsync =
        ref.watch(productVariantsProvider(_selectedProduct!.id));

    return variantsAsync.when(
      data: (variants) {
        if (variants.isEmpty) {
          return const Center(
            child: Text('No variants available for this product.'),
          );
        }

        return VariantSelector(
          variants: variants,
          selectedVariant: _selectedVariant,
          onVariantSelected: (variant) {
            setState(() {
              _selectedVariant = variant;
            });
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _buildOrderStep() {
    // Fetch recommended orders if product and variant are selected
    if (_selectedProduct == null || _selectedVariant == null) {
      return const Center(
        child: Text('Please select a product and variant first'),
      );
    }

    final recommendedOrdersAsync = ref.watch(
      recommendedOrdersProvider((
        productId: _selectedProduct!.id,
        variantId: _selectedVariant!.id,
      )),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sync orders button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recommended Orders',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            TextButton.icon(
              onPressed: () async {
                try {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Syncing orders from Shopify...'),
                      duration: Duration(seconds: 2),
                    ),
                  );

                  await ref.read(orderSyncNotifierProvider.notifier).sync();

                  // Refresh the recommended orders
                  ref.invalidate(recommendedOrdersProvider((
                    productId: _selectedProduct!.id,
                    variantId: _selectedVariant!.id,
                  )));

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Orders synced successfully'),
                        backgroundColor: SaturdayColors.success,
                      ),
                    );
                  }
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to sync orders: $error'),
                        backgroundColor: SaturdayColors.error,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Sync Orders'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Order list or loading/error states
        recommendedOrdersAsync.when(
          data: (orders) {
            return OrderSelector(
              orders: orders,
              selectedOrder: _selectedOrder,
              buildForInventory: _buildForInventory,
              onOrderSelected: (order) {
                setState(() {
                  _selectedOrder = order;
                  _buildForInventory = false;
                });
              },
              onBuildForInventory: () {
                setState(() {
                  _buildForInventory = true;
                  _selectedOrder = null;
                });
              },
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Center(
            child: Column(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: SaturdayColors.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load orders',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(recommendedOrdersProvider((
                      productId: _selectedProduct!.id,
                      variantId: _selectedVariant!.id,
                    )));
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmationStep() {
    if (_createdUnit == null) {
      // Show summary before creation
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to create production unit',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _buildSummaryCard(),
          const SizedBox(height: 16),
          Text(
            'Click Continue to generate QR code and create unit',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
        ],
      );
    }

    // Show created unit with QR code
    return Column(
      children: [
        QRCodeDisplay(
          qrCodeUrl: _createdUnit!.qrCodeUrl,
          unitId: _createdUnit!.unitId,
        ),
        const SizedBox(height: 24),
        _buildSummaryCard(),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryRow('Product', _selectedProduct?.name ?? '-'),
            const Divider(),
            _buildSummaryRow(
              'Variant',
              _selectedVariant?.getFormattedVariantName() ?? '-',
            ),
            const Divider(),
            _buildSummaryRow(
              'Order',
              _buildForInventory
                  ? 'Inventory Build'
                  : _selectedOrder?.shopifyOrderNumber ?? 'None',
            ),
            if (_createdUnit != null) ...[
              const Divider(),
              _buildSummaryRow('Unit ID', _createdUnit!.unitId),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printLabel() async {
    if (_createdUnit == null ||
        _selectedProduct == null ||
        _selectedVariant == null) {
      return;
    }

    try {
      // Download QR code image
      Uint8List? qrImageData;
      try {
        final response = await http.get(Uri.parse(_createdUnit!.qrCodeUrl));
        if (response.statusCode == 200) {
          qrImageData = response.bodyBytes;
        } else {
          // If download fails, generate QR code
          final qrService = QRService();
          qrImageData = await qrService.generateQRCode(
            _createdUnit!.uuid,
            size: 200,
          );
        }
      } catch (e) {
        AppLogger.error('Error loading QR code', e);
        // Generate QR code as fallback
        final qrService = QRService();
        qrImageData = await qrService.generateQRCode(
          _createdUnit!.uuid,
          size: 200,
        );
      }

      // Show print preview dialog
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => PrintPreviewDialog(
            unit: _createdUnit!,
            productName: _selectedProduct!.name,
            variantName: _selectedVariant!.name,
            qrImageData: qrImageData!,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error printing label', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
