import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';
import 'package:saturday_consumer_app/services/claude_vision_service.dart';

/// Unified camera screen for adding albums.
///
/// Supports:
/// - Automatic barcode detection with tap-to-search overlay
/// - Photo capture for album covers (coming soon)
/// - Manual search fallback
///
/// The camera automatically detects barcodes and shows a floating
/// overlay near the barcode (similar to iOS camera QR code detection).
/// Users tap the overlay to search for the album.
class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  late final MobileScannerController _scannerController;

  // Detected barcode state - shown as floating overlay
  String? _detectedBarcode;
  Rect? _barcodeRect;
  bool _isSearching = false;
  DateTime? _lastDetectionTime;

  @override
  void initState() {
    super.initState();

    // Initialize scanner for barcode detection
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    // Hide status bar for immersive camera experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scannerController.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isSearching) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) {
      // No barcode in view - clear detection after a short delay
      // This prevents flickering when barcode briefly leaves frame
      final lastTime = _lastDetectionTime;
      if (lastTime != null &&
          DateTime.now().difference(lastTime).inMilliseconds > 300) {
        if (_detectedBarcode != null) {
          setState(() {
            _detectedBarcode = null;
            _barcodeRect = null;
            _lastDetectionTime = null;
          });
        }
      }
      return;
    }

    // Update detection timestamp
    _lastDetectionTime = DateTime.now();

    final code = barcode.rawValue!;
    final corners = barcode.corners;

    // Calculate bounding rect from corners if available
    Rect? rect;
    if (corners.length == 4) {
      final screenSize = MediaQuery.of(context).size;

      // Get raw corner values
      final xs = corners.map((c) => c.dx).toList();
      final ys = corners.map((c) => c.dy).toList();

      double minX = xs.reduce((a, b) => a < b ? a : b);
      double minY = ys.reduce((a, b) => a < b ? a : b);
      double maxX = xs.reduce((a, b) => a > b ? a : b);
      double maxY = ys.reduce((a, b) => a > b ? a : b);

      // Get the actual image size from the capture
      final imageSize = capture.size;
      final double imageWidth = imageSize.width;
      final double imageHeight = imageSize.height;

      // The mobile_scanner returns corners in the image coordinate space.
      // For iOS portrait mode, the image is delivered already rotated to match screen orientation.
      // So we just need to scale from image coordinates to screen coordinates.
      final scaleX = screenSize.width / imageWidth;
      final scaleY = screenSize.height / imageHeight;

      final screenLeft = minX * scaleX;
      final screenTop = minY * scaleY;
      final screenWidth = (maxX - minX) * scaleX;
      final screenHeight = (maxY - minY) * scaleY;

      rect = Rect.fromLTWH(screenLeft, screenTop, screenWidth, screenHeight);
    }

    setState(() {
      _detectedBarcode = code;
      _barcodeRect = rect;
    });
  }

  void _onCancel() {
    ref.read(addAlbumProvider.notifier).reset();
    context.pop();
  }

  Future<void> _onCapturePhoto() async {
    // Check if vision service is available
    final visionService = ref.read(claudeVisionServiceProvider);
    if (visionService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Album cover recognition requires an Anthropic API key. '
            'Please add ANTHROPIC_API_KEY to your .env file.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
    });

    CameraController? cameraController;

    try {
      // Stop the barcode scanner to release the camera
      await _scannerController.stop();

      // Get available cameras and find back camera
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Initialize camera controller for photo capture
      cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await cameraController.initialize();

      // Take the photo immediately (camera is already focused from previous view)
      final XFile photo = await cameraController.takePicture();

      // Dispose camera controller to release resources
      await cameraController.dispose();
      cameraController = null;

      if (!mounted) return;

      // Read the image bytes
      final imageBytes = await File(photo.path).readAsBytes();

      // Clean up temp file
      try {
        await File(photo.path).delete();
      } catch (_) {}

      // Search by album cover using Claude Vision
      final identification = await ref
          .read(addAlbumProvider.notifier)
          .searchByAlbumCover(imageBytes);

      if (!mounted) return;

      final state = ref.read(addAlbumProvider);

      if (state.error != null) {
        // Show error
        _showErrorSnackbar(state.error!);
        await _scannerController.start();
        setState(() {
          _isSearching = false;
        });
      } else if (state.selectedAlbum != null) {
        // Auto-selected (single result), go to confirm
        context.push('/library/add/confirm');
      } else if (state.searchResults.isNotEmpty) {
        // Show what Claude identified and the results
        if (identification != null && identification.isSuccessful) {
          _showVisionResultsSheet(
            identification.artist ?? '',
            identification.albumTitle ?? '',
            state.searchResults,
          );
        } else {
          _showResultsSheet(state.searchResults);
        }
      } else {
        // No results found
        await _scannerController.start();
        _showNoVisionResultsDialog(identification);
      }
    } catch (e) {
      if (!mounted) return;

      // Dispose camera if still active
      if (cameraController != null) {
        try {
          await cameraController.dispose();
        } catch (_) {}
      }

      // Restart scanner on error
      try {
        await _scannerController.start();
      } catch (_) {}

      setState(() {
        _isSearching = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture photo: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showNoVisionResultsDialog(AlbumIdentificationResult? identification) {
    final identified = identification?.isSuccessful == true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(identified ? 'No Albums Found' : 'Could Not Identify Album'),
        content: Text(
          identified
              ? 'Found "${identification!.artist} - ${identification.albumTitle}" '
                  'but no matching vinyl records in Discogs.\n\n'
                  'Would you like to search manually?'
              : 'Could not identify the album from the photo.\n\n'
                  'Try taking a clearer photo or search manually.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isSearching = false;
              });
            },
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.pushReplacement('/library/add/search');
            },
            child: const Text('Search Manually'),
          ),
        ],
      ),
    );
  }

  void _showVisionResultsSheet(
      String artist, String album, List results) {
    setState(() {
      _isSearching = false;
    });

    // Capture parent context's router before entering the sheet
    final parentRouter = GoRouter.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (sheetContext, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                children: [
                  const Icon(Icons.auto_awesome, size: 28),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Identified: $artist',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    album,
                    style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                          color: Colors.grey,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '${results.length} versions found',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: results.length,
                itemBuilder: (itemContext, index) {
                  final result = results[index];
                  return _buildResultTile(result, sheetContext, parentRouter);
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // If sheet is dismissed without selection, reset state
      if (mounted && ref.read(selectedAlbumProvider) == null) {
        setState(() {
          _isSearching = false;
          _detectedBarcode = null;
          _barcodeRect = null;
        });
      }
    });
  }

  Future<void> _searchWithBarcode(String barcode) async {
    setState(() {
      _isSearching = true;
    });

    // Search by barcode
    await ref.read(addAlbumProvider.notifier).searchByBarcode(barcode);

    if (!mounted) return;

    final state = ref.read(addAlbumProvider);

    if (state.error != null) {
      // Show error and allow retry
      _showErrorSnackbar(state.error!);
      setState(() {
        _isSearching = false;
        _detectedBarcode = null;
        _barcodeRect = null;
      });
    } else if (state.selectedAlbum != null) {
      // Auto-selected (single result), go to confirm
      context.push('/library/add/confirm');
    } else if (state.searchResults.isNotEmpty) {
      // Multiple results, show selection
      _showResultsSheet(state.searchResults);
    } else {
      // No results found
      _showNoResultsDialog(barcode);
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            setState(() {
              _isSearching = false;
              _detectedBarcode = null;
            });
          },
        ),
      ),
    );
  }

  void _showNoResultsDialog(String barcode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Album Not Found'),
        content: Text(
          'No album found for barcode:\n$barcode\n\nWould you like to search manually instead?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isSearching = false;
                _detectedBarcode = null;
                _barcodeRect = null;
              });
            },
            child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.pushReplacement('/library/add/search');
            },
            child: const Text('Search Manually'),
          ),
        ],
      ),
    );
  }

  void _showResultsSheet(List results) {
    // Capture parent context's router before entering the sheet
    final parentRouter = GoRouter.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (sheetContext, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                children: [
                  Text(
                    'Select Your Pressing',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '${results.length} versions found',
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: results.length,
                itemBuilder: (itemContext, index) {
                  final result = results[index];
                  return _buildResultTile(result, sheetContext, parentRouter);
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // If sheet is dismissed without selection, reset state
      if (mounted && ref.read(selectedAlbumProvider) == null) {
        setState(() {
          _isSearching = false;
          _detectedBarcode = null;
          _barcodeRect = null;
        });
      }
    });
  }

  Widget _buildResultTile(
    dynamic result,
    BuildContext sheetContext,
    GoRouter parentRouter,
  ) {
    // Build the metadata line with year, country, format
    final metadataParts = <String>[
      if (result.year != null) result.year!,
      if (result.country != null) result.country!,
      if (result.formats.isNotEmpty) result.formats.first,
    ];

    // Build the label/catalog line
    final labelParts = <String>[
      if (result.labels.isNotEmpty) result.labels.first,
      if (result.catno != null && result.catno!.isNotEmpty) result.catno!,
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      leading: ClipRRect(
        borderRadius: AppRadius.smallRadius,
        child: SizedBox(
          width: 56,
          height: 56,
          child: result.coverImageUrl != null
              ? CachedNetworkImage(
                  imageUrl: result.coverImageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _buildCoverPlaceholder(),
                  errorWidget: (context, url, error) => _buildCoverPlaceholder(),
                )
              : _buildCoverPlaceholder(),
        ),
      ),
      title: Text(
        result.albumTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          if (metadataParts.isNotEmpty)
            Text(
              metadataParts.join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          if (labelParts.isNotEmpty)
            Text(
              labelParts.join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        // Close the bottom sheet first
        Navigator.of(sheetContext).pop();
        // Select the album
        await ref
            .read(addAlbumProvider.notifier)
            .selectFromSearchResult(result);
        // Navigate using the parent context's router
        if (mounted) {
          parentRouter.push('/library/add/confirm');
        }
      },
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Icon(
        Icons.album,
        color: SaturdayColors.secondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(isAddingAlbumProvider) || _isSearching;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen camera preview
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
          ),

          // Top controls (cancel, flash)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopControls(),
          ),

          // Barcode detection overlay (iOS-style floating button)
          if (_detectedBarcode != null && !_isSearching)
            _buildBarcodeOverlay(),

          // Loading indicator
          if (isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.white,
                    ),
                    SizedBox(height: Spacing.lg),
                    Text(
                      'Searching...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom controls (instructions, capture button, manual entry)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + Spacing.sm,
        left: Spacing.md,
        right: Spacing.md,
        bottom: Spacing.sm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Cancel button
          TextButton.icon(
            onPressed: _onCancel,
            icon: const Icon(Icons.close, color: Colors.white),
            label: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          // Flash toggle
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _scannerController,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                  color: Colors.white,
                  size: 28,
                );
              },
            ),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeOverlay() {
    // iOS-style yellow box around barcode with callout pill below
    const borderColor = Color(0xFFFFD60A); // iOS yellow
    const pillColor = Color(0xFFFFD60A);

    // If we don't have position info, show a centered fallback
    if (_barcodeRect == null) {
      return Positioned(
        top: MediaQuery.of(context).size.height * 0.35,
        left: 0,
        right: 0,
        child: Center(
          child: GestureDetector(
            onTap: () => _searchWithBarcode(_detectedBarcode!),
            child: _buildCalloutPill(pillColor),
          ),
        ),
      );
    }

    // Scale the barcode rect from camera coordinates to screen coordinates
    final screenSize = MediaQuery.of(context).size;
    final rect = _barcodeRect!;

    // Add padding around the barcode box
    const padding = 12.0;
    const minWidth = 60.0;
    const minHeight = 40.0;

    final left = (rect.left - padding).clamp(0.0, screenSize.width - minWidth);
    final top = (rect.top - padding).clamp(0.0, screenSize.height - minHeight);
    final maxWidth = screenSize.width - left;
    final maxHeight = screenSize.height - top;
    final width = (rect.width + padding * 2).clamp(minWidth, maxWidth > minWidth ? maxWidth : minWidth);
    final height = (rect.height + padding * 2).clamp(minHeight, maxHeight > minHeight ? maxHeight : minHeight);

    return Stack(
      children: [
        // Yellow rounded rectangle around the barcode
        Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            onTap: () => _searchWithBarcode(_detectedBarcode!),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                border: Border.all(
                  color: borderColor,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        // Callout pill below the barcode box
        Positioned(
          left: left,
          top: top + height + 8,
          child: GestureDetector(
            onTap: () => _searchWithBarcode(_detectedBarcode!),
            child: _buildCalloutPill(pillColor),
          ),
        ),
      ],
    );
  }

  Widget _buildCalloutPill(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search,
            color: Colors.black87,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            'Search barcode',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.only(
        top: Spacing.xl,
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: MediaQuery.of(context).padding.bottom + Spacing.lg,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Instructions
          Text(
            'Scan a barcode or take a photo of the album cover',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Barcodes are usually on the back of the sleeve',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.xl),

          // Capture button row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Manual entry button
              _buildActionButton(
                icon: Icons.edit,
                label: 'Manual',
                onTap: () => context.pushReplacement('/library/add/search'),
              ),

              // Capture photo button (large center button)
              GestureDetector(
                onTap: _onCapturePhoto,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // Placeholder for symmetry (or could add gallery button later)
              const SizedBox(width: 64),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
