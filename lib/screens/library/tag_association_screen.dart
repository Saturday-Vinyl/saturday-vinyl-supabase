import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/tag_provider.dart';
import 'package:saturday_consumer_app/utils/epc_validator.dart';
import 'package:saturday_consumer_app/widgets/scanner/qr_scanner.dart';

/// Screen for associating an RFID tag with a library album via QR code scan.
class TagAssociationScreen extends ConsumerStatefulWidget {
  const TagAssociationScreen({
    super.key,
    required this.libraryAlbumId,
  });

  /// The ID of the library album to associate with a tag.
  final String libraryAlbumId;

  @override
  ConsumerState<TagAssociationScreen> createState() =>
      _TagAssociationScreenState();
}

class _TagAssociationScreenState extends ConsumerState<TagAssociationScreen> {
  @override
  void dispose() {
    ref.read(tagAssociationProvider.notifier).reset();
    super.dispose();
  }

  void _onQrDetected(String code) {
    // Defer state update to avoid rebuilding during frame
    Future.microtask(() {
      if (mounted) {
        ref.read(tagAssociationProvider.notifier).processQrCode(code);
      }
    });
  }

  Future<void> _confirmAssociation() async {
    final success = await ref
        .read(tagAssociationProvider.notifier)
        .associateTag(widget.libraryAlbumId);

    if (mounted && success) {
      final albumAsync =
          ref.read(libraryAlbumByIdProvider(widget.libraryAlbumId));
      final albumTitle =
          albumAsync.valueOrNull?.album?.title ?? 'album';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tag associated with "$albumTitle"'),
        ),
      );
      context.pop();
    }
  }

  void _resetAndScanAgain() {
    ref.read(tagAssociationProvider.notifier).reset();
    // Note: Can't call reset on scanner because it's re-rendered
  }

  void _onScanningResumed() {
    // Defer state update to avoid rebuilding during frame
    Future.microtask(() {
      if (mounted) {
        ref.read(tagAssociationProvider.notifier).acknowledgeContinueScanning();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tagAssociationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Associate Tag'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: state.scannedEpc != null
          ? _buildConfirmationView(state)
          : _buildScannerView(state),
    );
  }

  Widget _buildScannerView(TagAssociationState state) {
    return Stack(
      children: [
        QrScanner(
          onDetect: _onQrDetected,
          scanningMessage: 'Scan the QR code on your Saturday tag',
          shouldContinueScanning: state.shouldContinueScanning,
          onScanningResumed: _onScanningResumed,
        ),

        // Error message overlay
        if (state.error != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: SaturdayColors.error,
              padding: const EdgeInsets.all(Spacing.md),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        // Clear error and resume scanning
                        ref.read(tagAssociationProvider.notifier).clearError();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Loading indicator
        if (state.isLoading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildConfirmationView(TagAssociationState state) {
    final albumAsync =
        ref.watch(libraryAlbumByIdProvider(widget.libraryAlbumId));

    return SafeArea(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.xl),

            // Success icon
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: SaturdayColors.success,
            ),
            const SizedBox(height: Spacing.lg),

            // Title
            Text(
              'Tag Detected',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.md),

            // EPC display
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: SaturdayColors.secondary.withValues(alpha: 0.1),
                borderRadius: AppRadius.mediumRadius,
              ),
              child: Column(
                children: [
                  Text(
                    'Tag ID',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    EpcValidator.formatEpcForDisplay(state.scannedEpc!),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xl),


            // Album info
            albumAsync.when(
              data: (album) => album != null
                  ? _buildAlbumPreview(album.album?.title ?? 'Unknown Album',
                      album.album?.artist ?? 'Unknown Artist')
                  : const SizedBox.shrink(),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const Spacer(),

            // Error message
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Text(
                  state.error!,
                  style: TextStyle(color: SaturdayColors.error),
                  textAlign: TextAlign.center,
                ),
              ),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        state.isAssociating ? null : _resetAndScanAgain,
                    child: const Text('Scan Again'),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: state.isAssociating ? null : _confirmAssociation,
                    child: state.isAssociating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Associate Tag'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumPreview(String title, String artist) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: SaturdayColors.light,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(
          color: SaturdayColors.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Associate with:',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            artist,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
        ],
      ),
    );
  }
}
