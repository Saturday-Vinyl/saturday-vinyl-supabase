import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/product_image_asset.dart';
import 'package:saturday_app/models/product_image_slot.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/providers/image_slot_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/screens/products/image_slots/image_slot_editor_screen.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

const _angles = ['front', 'angle', 'top'];
const _capacities = ['full', 'half', 'empty'];

/// Screen for selecting a product/angle/capacity and managing frame image assets
/// before launching the WYSIWYG slot editor.
class ImageSlotSelectionScreen extends ConsumerStatefulWidget {
  final String productId;

  const ImageSlotSelectionScreen({super.key, required this.productId});

  @override
  ConsumerState<ImageSlotSelectionScreen> createState() =>
      _ImageSlotSelectionScreenState();
}

class _ImageSlotSelectionScreenState
    extends ConsumerState<ImageSlotSelectionScreen> {
  String _selectedAngle = 'front';
  String _selectedCapacity = 'full';
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productProvider(widget.productId));
    final variantsAsync =
        ref.watch(productVariantsProvider(widget.productId));
    final slotsAsync =
        ref.watch(productImageSlotsProvider(widget.productId));
    final assetsAsync =
        ref.watch(productImageAssetsProvider(widget.productId));

    return Scaffold(
      appBar: AppBar(title: const Text('Image Slot Editor')),
      body: productAsync.when(
        data: (product) {
          if (product == null) {
            return const ErrorState(message: 'Product not found');
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product header
                Text(
                  product.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                const SizedBox(height: 24),

                // Angle selector
                Text('View Angle',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: _angles
                      .map((a) => ButtonSegment(value: a, label: Text(a)))
                      .toList(),
                  selected: {_selectedAngle},
                  onSelectionChanged: (s) =>
                      setState(() => _selectedAngle = s.first),
                ),
                const SizedBox(height: 20),

                // Capacity selector
                Text('Capacity',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: _capacities
                      .map((c) => ButtonSegment(value: c, label: Text(c)))
                      .toList(),
                  selected: {_selectedCapacity},
                  onSelectionChanged: (s) =>
                      setState(() => _selectedCapacity = s.first),
                ),
                const SizedBox(height: 24),

                const Divider(),
                const SizedBox(height: 16),

                // Slot status grid
                Text('Configured Slots',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                slotsAsync.when(
                  data: (slots) => _buildSlotStatusGrid(context, slots),
                  loading: () =>
                      const LoadingIndicator(message: 'Loading slots...'),
                  error: (e, _) => Text('Error: $e'),
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // Variant frame images
                Text('Frame Images for "$_selectedAngle"',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                variantsAsync.when(
                  data: (variants) => assetsAsync.when(
                    data: (assets) => _buildVariantAssetList(
                      context,
                      product,
                      variants,
                      assets,
                    ),
                    loading: () => const LoadingIndicator(
                        message: 'Loading assets...'),
                    error: (e, _) => Text('Error: $e'),
                  ),
                  loading: () => const LoadingIndicator(
                      message: 'Loading variants...'),
                  error: (e, _) => Text('Error: $e'),
                ),

                const SizedBox(height: 24),

                // Open Editor button
                assetsAsync.when(
                  data: (assets) {
                    final angleAssets = assets
                        .where((a) => a.angle == _selectedAngle)
                        .toList();
                    if (angleAssets.isEmpty) {
                      return const Text(
                        'Upload at least one frame image for this angle before editing slots.',
                        style: TextStyle(color: SaturdayColors.secondaryGrey),
                      );
                    }

                    final asset = angleAssets.first;
                    final existingSlot = slotsAsync.valueOrNull?.where((s) =>
                        s.angle == _selectedAngle &&
                        s.capacity == _selectedCapacity).firstOrNull;

                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _openEditor(
                          context,
                          product,
                          asset,
                          existingSlot,
                        ),
                        icon: const Icon(Icons.edit),
                        label: Text(existingSlot != null
                            ? 'Edit Slot ($_selectedAngle / $_selectedCapacity)'
                            : 'Create Slot ($_selectedAngle / $_selectedCapacity)'),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
        loading: () => const LoadingIndicator(message: 'Loading product...'),
        error: (error, stack) => ErrorState(
          message: 'Failed to load product',
          details: error.toString(),
          onRetry: () => ref.invalidate(productProvider(widget.productId)),
        ),
      ),
    );
  }

  Widget _buildSlotStatusGrid(
      BuildContext context, List<ProductImageSlot> slots) {
    return Table(
      border: TableBorder.all(color: SaturdayColors.light),
      columnWidths: const {
        0: FixedColumnWidth(80),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: SaturdayColors.light),
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ..._capacities.map((c) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(c,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                )),
          ],
        ),
        ..._angles.map((angle) {
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(angle,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ..._capacities.map((cap) {
                final hasSlot = slots.any(
                    (s) => s.angle == angle && s.capacity == cap);
                final isSelected = angle == _selectedAngle &&
                    cap == _selectedCapacity;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedAngle = angle;
                    _selectedCapacity = cap;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? SaturdayColors.info.withValues(alpha: 0.15)
                          : null,
                      border: isSelected
                          ? Border.all(color: SaturdayColors.info, width: 2)
                          : null,
                    ),
                    child: Icon(
                      hasSlot ? Icons.check_circle : Icons.circle_outlined,
                      color: hasSlot
                          ? SaturdayColors.success
                          : SaturdayColors.secondaryGrey,
                      size: 20,
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildVariantAssetList(
    BuildContext context,
    Product product,
    List<ProductVariant> variants,
    List<ProductImageAsset> assets,
  ) {
    final activeVariants = variants.where((v) => v.isActive).toList();
    if (activeVariants.isEmpty) {
      return const Text('No active variants',
          style: TextStyle(color: SaturdayColors.secondaryGrey));
    }

    return Column(
      children: activeVariants.map((variant) {
        final asset = assets.where(
            (a) => a.variantId == variant.id && a.angle == _selectedAngle).firstOrNull;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: asset != null
                ? const Icon(Icons.image, color: SaturdayColors.success)
                : const Icon(Icons.image_not_supported,
                    color: SaturdayColors.secondaryGrey),
            title: Text(variant.getFormattedVariantName()),
            subtitle: Text(asset != null
                ? '${asset.imageWidth}x${asset.imageHeight} — ${asset.framePath}'
                : 'No frame image for $_selectedAngle'),
            trailing: _isUploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.upload_file),
                    tooltip: 'Upload frame image',
                    onPressed: () => _uploadFrameImage(
                      product,
                      variant,
                    ),
                  ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _uploadFrameImage(
    Product product,
    ProductVariant variant,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _isUploading = true);

    try {
      final bytes = file.bytes!;

      // Decode image to get dimensions
      final decoded = img.decodePng(bytes);
      if (decoded == null) {
        throw Exception('Failed to decode PNG');
      }

      // Upload to Supabase Storage
      final storagePath =
          '${product.shopifyProductHandle}/${variant.sku}/$_selectedAngle.png';

      await SupabaseService.instance.client.storage
          .from('product-images')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );

      // Upsert the asset record
      await ref.read(imageSlotManagementProvider).saveAsset(
            variantId: variant.id,
            productId: widget.productId,
            angle: _selectedAngle,
            framePath: storagePath,
            imageWidth: decoded.width,
            imageHeight: decoded.height,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Frame image uploaded'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upload frame image', error, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _openEditor(
    BuildContext context,
    Product product,
    ProductImageAsset asset,
    ProductImageSlot? existingSlot,
  ) {
    final frameUrl = ref.read(frameImageUrlProvider(asset.framePath));

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageSlotEditorScreen(
          productId: widget.productId,
          productName: product.name,
          angle: _selectedAngle,
          capacity: _selectedCapacity,
          frameImageUrl: frameUrl,
          imageWidth: asset.imageWidth,
          imageHeight: asset.imageHeight,
          existingSlotData: existingSlot?.slotData,
        ),
      ),
    );
  }
}

