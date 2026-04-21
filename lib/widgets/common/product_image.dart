import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/services/product_image_service.dart';
import 'package:saturday_consumer_app/widgets/common/product_composite_painter.dart';

/// Resolves a [CachedNetworkImageProvider] to a [ui.Image].
Future<ui.Image> _resolveNetworkImage(String url) {
  final completer = Completer<ui.Image>();
  final provider = CachedNetworkImageProvider(url);
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      completer.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (error, stackTrace) {
      completer.completeError(error, stackTrace);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// A widget that displays a product image with optional album cover compositing.
///
/// Loads the product frame image (and optionally an album cover), then
/// uses [ProductCompositePainter] to composite them together using
/// perspective transform and clip path data from [ProductImageSlot].
class ProductImageWidget extends StatefulWidget {
  final Device device;
  final String? albumCoverUrl;
  final String angle;
  final String capacity;
  final double size;
  final Widget? fallback;

  const ProductImageWidget({
    super.key,
    required this.device,
    this.albumCoverUrl,
    this.angle = 'front',
    this.capacity = 'full',
    this.size = 48,
    this.fallback,
  });

  @override
  State<ProductImageWidget> createState() => _ProductImageWidgetState();
}

class _ProductImageWidgetState extends State<ProductImageWidget> {
  ui.Image? _frameImage;
  ui.Image? _albumImage;
  ProductImageSlot? _slot;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void didUpdateWidget(ProductImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.sku != widget.device.sku ||
        oldWidget.device.productHandle != widget.device.productHandle ||
        oldWidget.angle != widget.angle ||
        oldWidget.capacity != widget.capacity ||
        oldWidget.albumCoverUrl != widget.albumCoverUrl) {
      _disposeImages();
      _loadImages();
    }
  }

  @override
  void dispose() {
    _disposeImages();
    super.dispose();
  }

  void _disposeImages() {
    _frameImage?.dispose();
    _albumImage?.dispose();
    _frameImage = null;
    _albumImage = null;
  }

  Future<void> _loadImages() async {
    if (!widget.device.hasProductImageData) {
      setState(() {
        _loading = false;
        _hasError = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _hasError = false;
    });

    try {
      // Fetch asset metadata (for frame URL) and slot data in parallel
      final assetFuture = widget.device.variantId != null
          ? ProductImageService.getAsset(
              variantId: widget.device.variantId!,
              angle: widget.angle,
            )
          : Future.value(null);

      final slotFuture = widget.device.productId != null
          ? ProductImageService.getSlot(
              productId: widget.device.productId!,
              angle: widget.angle,
              capacity: widget.capacity,
            )
          : Future.value(null);

      final results = await Future.wait([assetFuture, slotFuture]);
      final asset = results[0] as ProductImageAsset?;
      final slot = results[1] as ProductImageSlot?;

      // Determine frame URL
      final frameUrl = asset?.frameUrl ??
          ProductImageService.frameUrl(
            widget.device.productHandle!,
            widget.device.sku!,
            widget.angle,
          );

      // Load frame (required)
      final frameImage = await _resolveNetworkImage(frameUrl);

      // Load album if compositing is possible
      ui.Image? albumImage;
      final shouldComposite =
          widget.albumCoverUrl != null && widget.size > 64 && slot?.isValid == true;

      if (shouldComposite) {
        try {
          albumImage = await _resolveNetworkImage(widget.albumCoverUrl!);
        } catch (_) {
          // Album failed to load — render frame only
        }
      }

      if (!mounted) {
        frameImage.dispose();
        albumImage?.dispose();
        return;
      }

      setState(() {
        _frameImage = frameImage;
        _albumImage = albumImage;
        _slot = slot;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Widget _buildFallback() {
    return widget.fallback ??
        Icon(
          widget.device.isHub ? Icons.router : Icons.inventory_2_outlined,
          size: widget.size * 0.5,
        );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_hasError || _frameImage == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(child: _buildFallback()),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: ProductCompositePainter(
            frameImage: _frameImage!,
            albumImage: _albumImage,
            transformCorners: _slot?.transform,
            clipPoints: _slot?.clip,
          ),
        ),
      ),
    );
  }
}
