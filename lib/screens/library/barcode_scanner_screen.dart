import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';

/// Screen for scanning barcodes to find albums.
class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _hasScanned = false;
  String? _lastScannedCode;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_hasScanned) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!;

    // Avoid duplicate scans of the same code
    if (code == _lastScannedCode) return;

    setState(() {
      _hasScanned = true;
      _lastScannedCode = code;
    });

    // Stop scanning
    await _scannerController.stop();

    // Search by barcode
    await ref.read(addAlbumProvider.notifier).searchByBarcode(code);

    if (!mounted) return;

    final state = ref.read(addAlbumProvider);

    if (state.error != null) {
      // Show error and allow retry
      _showErrorSnackbar(state.error!);
      _resetScanner();
    } else if (state.selectedAlbum != null) {
      // Auto-selected (single result), go to confirm
      context.pushReplacement('/library/add/confirm');
    } else if (state.searchResults.isNotEmpty) {
      // Multiple results, show selection
      _showResultsSheet(state.searchResults);
    } else {
      // No results found
      _showNoResultsDialog(code);
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: _resetScanner,
        ),
      ),
    );
  }

  void _resetScanner() async {
    setState(() {
      _hasScanned = false;
      _lastScannedCode = null;
    });
    await _scannerController.start();
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
              _resetScanner();
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                'Multiple results found',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  return ListTile(
                    title: Text(result.albumTitle),
                    subtitle: Text(result.artist),
                    trailing: result.year != null ? Text(result.year!) : null,
                    onTap: () async {
                      final navigator = Navigator.of(context);
                      final router = GoRouter.of(context);
                      navigator.pop();
                      await ref
                          .read(addAlbumProvider.notifier)
                          .selectFromSearchResult(result);
                      if (mounted) {
                        router.pushReplacement('/library/add/confirm');
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // If sheet is dismissed without selection, reset scanner
      if (mounted && ref.read(selectedAlbumProvider) == null) {
        _resetScanner();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(isAddingAlbumProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(addAlbumProvider.notifier).reset();
            context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _scannerController,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
          ),

          // Overlay with scanning area indicator
          _buildScanOverlay(),

          // Loading indicator
          if (isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),

          // Instructions
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildInstructions(),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.7;
        final scanAreaTop = (constraints.maxHeight - scanAreaSize) / 2 - 50;

        return Stack(
          children: [
            // Dark overlay with cutout
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black54,
                BlendMode.srcOut,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: scanAreaTop,
                    left: (constraints.maxWidth - scanAreaSize) / 2,
                    child: Container(
                      width: scanAreaSize,
                      height: scanAreaSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scan area border
            Positioned(
              top: scanAreaTop,
              left: (constraints.maxWidth - scanAreaSize) / 2,
              child: Container(
                width: scanAreaSize,
                height: scanAreaSize,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: SaturdayColors.primaryDark,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Point your camera at the barcode',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'The barcode is usually on the back of the album cover or sleeve',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.lg),
            TextButton.icon(
              onPressed: () => context.pushReplacement('/library/add/search'),
              icon: const Icon(Icons.search, color: Colors.white),
              label: const Text(
                'Search manually instead',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
