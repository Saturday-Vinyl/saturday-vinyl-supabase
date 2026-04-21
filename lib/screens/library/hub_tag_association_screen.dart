import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/hub_tag_association_provider.dart';
import 'package:saturday_consumer_app/providers/tag_provider.dart';
import 'package:saturday_consumer_app/utils/epc_validator.dart';

/// Screen for associating an RFID tag with a library album via hub scan.
///
/// The user selects a hub (or auto-selects if only one), places a tag on it,
/// and the backend detects the tag and returns the EPC for association.
class HubTagAssociationScreen extends ConsumerStatefulWidget {
  const HubTagAssociationScreen({
    super.key,
    required this.libraryAlbumId,
  });

  final String libraryAlbumId;

  @override
  ConsumerState<HubTagAssociationScreen> createState() =>
      _HubTagAssociationScreenState();
}

class _HubTagAssociationScreenState
    extends ConsumerState<HubTagAssociationScreen> {
  @override
  void initState() {
    super.initState();
    // Clear any stale state from a previous association
    ref.read(tagAssociationProvider.notifier).reset();
    ref.read(hubTagAssociationProvider.notifier).reset();
  }

  @override
  void dispose() {
    ref.read(tagAssociationProvider.notifier).reset();
    super.dispose();
  }

  Future<void> _cancelAndPop() async {
    await ref.read(hubTagAssociationProvider.notifier).cancel();
    if (mounted) context.pop();
  }

  void _selectHub(Device hub) {
    ref
        .read(hubTagAssociationProvider.notifier)
        .startWaiting(hub, widget.libraryAlbumId);
  }

  void _onEpcDetected(String epc) {
    ref.read(tagAssociationProvider.notifier).processHubDetectedEpc(epc);
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

      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Tag associated with "$albumTitle"'),
          ),
        );
      context.pop();
    }
  }

  void _tryAgain() {
    ref.read(tagAssociationProvider.notifier).reset();
    ref.read(hubTagAssociationProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    final hubState = ref.watch(hubTagAssociationProvider);
    final tagState = ref.watch(tagAssociationProvider);

    // When hub detects an EPC, hand it to the tag association notifier
    ref.listen<HubTagAssociationState>(hubTagAssociationProvider,
        (previous, next) {
      if (next.detectedEpc != null &&
          previous?.detectedEpc != next.detectedEpc) {
        _onEpcDetected(next.detectedEpc!);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Associate Tag'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelAndPop,
        ),
      ),
      body: _buildBody(hubState, tagState),
    );
  }

  Widget _buildBody(
      HubTagAssociationState hubState, TagAssociationState tagState) {
    // If we have a scanned EPC (from hub), show confirmation
    if (tagState.scannedEpc != null) {
      return _buildConfirmationView(tagState);
    }

    // If waiting for hub scan
    if (hubState.isWaiting) {
      return _buildWaitingView(hubState);
    }

    // Otherwise, show hub selection
    return _buildHubSelectionView(hubState);
  }

  Widget _buildHubSelectionView(HubTagAssociationState hubState) {
    final hubsAsync = ref.watch(userHubsProvider);

    return SafeArea(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.xl),
            Icon(
              Icons.router_outlined,
              size: 64,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Select a Hub',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Choose which hub to use for reading the tag.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),

            if (hubState.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Text(
                  hubState.error!,
                  style: TextStyle(color: SaturdayColors.error),
                  textAlign: TextAlign.center,
                ),
              ),

            hubsAsync.when(
              data: (hubs) {
                if (hubs.isEmpty) {
                  return _buildNoHubsMessage();
                }

                // Auto-select if only one hub
                if (hubs.length == 1) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _selectHub(hubs.first);
                  });
                  return const Center(child: CircularProgressIndicator());
                }

                return Expanded(
                  child: ListView.separated(
                    itemCount: hubs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, index) {
                      final hub = hubs[index];
                      return _buildHubTile(hub);
                    },
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(
                'Failed to load hubs: $e',
                style: TextStyle(color: SaturdayColors.error),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubTile(Device hub) {
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.router,
          color: hub.isOnline ? SaturdayColors.success : SaturdayColors.secondary,
        ),
        title: Text(hub.name),
        subtitle: Text(
          hub.isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            color: hub.isOnline
                ? SaturdayColors.success
                : SaturdayColors.secondary,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        enabled: hub.isOnline,
        onTap: hub.isOnline ? () => _selectHub(hub) : null,
      ),
    );
  }

  Widget _buildNoHubsMessage() {
    return Column(
      children: [
        const SizedBox(height: Spacing.xl),
        Text(
          'No hubs found',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          'You need a Saturday Hub to use this feature. '
          'Try scanning the QR code on the tag instead.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SaturdayColors.secondary,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildWaitingView(HubTagAssociationState hubState) {
    return SafeArea(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),

            // Animated hub icon
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              onEnd: () {
                // Restart animation by triggering rebuild
                if (mounted && hubState.isWaiting) {
                  setState(() {});
                }
              },
              child: Icon(
                Icons.nfc_rounded,
                size: 100,
                color: SaturdayColors.primaryDark,
              ),
            ),
            const SizedBox(height: Spacing.xl),

            Text(
              'Place your tag on',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              hubState.selectedHub?.name ?? 'your hub',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: SaturdayColors.primaryDark,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'The hub will read the tag and identify it for you.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),

            if (hubState.error != null) ...[
              const SizedBox(height: Spacing.lg),
              Text(
                hubState.error!,
                style: TextStyle(color: SaturdayColors.error),
                textAlign: TextAlign.center,
              ),
            ],

            const Spacer(),

            // Cancel button
            OutlinedButton(
              onPressed: _cancelAndPop,
              child: const Text('Cancel'),
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
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

            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: SaturdayColors.success,
            ),
            const SizedBox(height: Spacing.lg),

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
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
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
                    onPressed: state.isAssociating ? null : _tryAgain,
                    child: const Text('Try Again'),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        state.isAssociating ? null : _confirmAssociation,
                    child: state.isAssociating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
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
