import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/slot_data.dart';
import 'package:saturday_app/providers/image_slot_provider.dart';
import 'package:saturday_app/providers/slot_editor_state_provider.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/products/image_slots/slot_editor_canvas.dart';
import 'package:saturday_app/widgets/products/image_slots/slot_editor_toolbar.dart';

/// WYSIWYG editor for defining album compositing slot geometry.
class ImageSlotEditorScreen extends ConsumerStatefulWidget {
  final String productId;
  final String productName;
  final String angle;
  final String capacity;
  final String frameImageUrl;
  final int imageWidth;
  final int imageHeight;
  final SlotData? existingSlotData;

  const ImageSlotEditorScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.angle,
    required this.capacity,
    required this.frameImageUrl,
    required this.imageWidth,
    required this.imageHeight,
    this.existingSlotData,
  });

  @override
  ConsumerState<ImageSlotEditorScreen> createState() =>
      _ImageSlotEditorScreenState();
}

class _ImageSlotEditorScreenState
    extends ConsumerState<ImageSlotEditorScreen> {
  ui.Image? _frameImage;
  ui.Image? _sampleAlbum;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      // Load frame image from network
      final frameBytes = await _fetchImageBytes(widget.frameImageUrl);
      _frameImage = await _decodeImage(frameBytes);
      AppLogger.info('Frame image loaded: ${_frameImage!.width}x${_frameImage!.height}');

      // Load sample album from bundled asset
      final albumData = await rootBundle.load('assets/images/sample_album.png');
      AppLogger.info('Sample album asset loaded: ${albumData.lengthInBytes} bytes');
      _sampleAlbum = await _decodeImage(albumData.buffer.asUint8List());
      AppLogger.info('Sample album decoded: ${_sampleAlbum!.width}x${_sampleAlbum!.height}');

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load editor images', error, stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = error.toString();
        });
      }
    }
  }

  Future<Uint8List> _fetchImageBytes(String url) async {
    AppLogger.info('Fetching frame image: $url');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      AppLogger.error('Frame image fetch failed: HTTP ${response.statusCode}, URL: $url, Body: ${response.body}');
      throw Exception('Failed to fetch image: HTTP ${response.statusCode} from $url');
    }
    return response.bodyBytes;
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading Editor...')),
        body: const LoadingIndicator(message: 'Loading images...'),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Image Slot Editor')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: SaturdayColors.error),
              const SizedBox(height: 16),
              Text('Failed to load images: $_loadError'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _loadError = null;
                  });
                  _loadImages();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final initialSlotData = widget.existingSlotData ??
        SlotData.defaultForSize(
          widget.imageWidth.toDouble(),
          widget.imageHeight.toDouble(),
        );

    return ProviderScope(
      overrides: [
        slotEditorProvider.overrideWith(
          (ref) => SlotEditorNotifier(initialSlotData),
        ),
      ],
      child: _EditorBody(
        productId: widget.productId,
        productName: widget.productName,
        angle: widget.angle,
        capacity: widget.capacity,
        frameImage: _frameImage,
        sampleAlbumImage: _sampleAlbum,
        imageWidth: widget.imageWidth,
        imageHeight: widget.imageHeight,
      ),
    );
  }
}

/// Inner widget that lives inside the overridden ProviderScope.
class _EditorBody extends ConsumerWidget {
  final String productId;
  final String productName;
  final String angle;
  final String capacity;
  final ui.Image? frameImage;
  final ui.Image? sampleAlbumImage;
  final int imageWidth;
  final int imageHeight;

  const _EditorBody({
    required this.productId,
    required this.productName,
    required this.angle,
    required this.capacity,
    required this.frameImage,
    required this.sampleAlbumImage,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(slotEditorProvider);

    return PopScope(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved Changes'),
            content: const Text(
                'You have unsaved changes. Discard them?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                    foregroundColor: SaturdayColors.error),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (shouldLeave == true && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('$productName — $angle / $capacity'),
        ),
        body: Column(
          children: [
            SlotEditorToolbar(
              onSave: () => _save(context, ref),
              onAddClipPoint: () {
                // Add a point at center of the image
                final center = Offset(
                  imageWidth / 2.0,
                  imageHeight / 2.0,
                );
                ref.read(slotEditorProvider.notifier).addClipPoint(center);
              },
            ),
            Expanded(
              child: SlotEditorCanvas(
                frameImage: frameImage,
                sampleAlbumImage: sampleAlbumImage,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(slotEditorProvider.notifier);
    final state = ref.read(slotEditorProvider);
    final slotData = state.toSlotData();

    if (!slotData.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Invalid slot data: transform needs 4 points, clip needs at least 3'),
          backgroundColor: SaturdayColors.error,
        ),
      );
      return;
    }

    notifier.setSaving(true);

    try {
      await ref.read(imageSlotManagementProvider).saveSlot(
            productId: productId,
            angle: angle,
            capacity: capacity,
            slotData: slotData,
          );

      notifier.markClean();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Slot saved'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      notifier.setSaving(false);
    }
  }
}
