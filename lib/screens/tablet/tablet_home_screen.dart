import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/screens/library/library_screen.dart';
import 'package:saturday_consumer_app/screens/now_playing/now_playing_screen.dart';
import 'package:saturday_consumer_app/widgets/common/adaptive_layout.dart';
import 'package:saturday_consumer_app/widgets/library/album_detail_panel.dart';

/// A provider to track selected album in tablet layout.
///
/// When set, the tablet layout will show the album detail panel
/// instead of navigating to a full-screen detail view.
final tabletSelectedAlbumIdProvider = StateProvider<String?>((ref) => null);

/// Tablet home screen showing Now Playing and Library side-by-side in landscape.
///
/// In portrait mode, falls back to standard tab navigation.
class TabletHomeScreen extends ConsumerWidget {
  const TabletHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OrientationBuilder2(
      // Portrait: Show standard navigation (handled by parent)
      portrait: (_) => const _PortraitLayout(),
      // Landscape: Show dual-pane layout
      landscape: (_) => const _LandscapeLayout(),
    );
  }
}

/// Portrait layout for tablet - single pane similar to phone.
class _PortraitLayout extends StatelessWidget {
  const _PortraitLayout();

  @override
  Widget build(BuildContext context) {
    // In portrait, we use the standard tab-based navigation
    // This widget would be replaced by the normal scaffold with nav
    return const NowPlayingScreen();
  }
}

/// Landscape layout for tablet - dual pane with Now Playing and Library.
class _LandscapeLayout extends ConsumerWidget {
  const _LandscapeLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAlbumId = ref.watch(tabletSelectedAlbumIdProvider);

    return Row(
      children: [
        // Left pane: Now Playing (narrower)
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: SaturdayColors.secondary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: const NowPlayingScreen(),
          ),
        ),

        // Right pane: Library or Album Detail
        Expanded(
          flex: 3,
          child: selectedAlbumId != null
              ? AlbumDetailPanel(
                  libraryAlbumId: selectedAlbumId,
                  onClose: () {
                    ref.read(tabletSelectedAlbumIdProvider.notifier).state =
                        null;
                  },
                  onSetAsNowPlaying: () {
                    // Album is set as now playing - could close panel or keep it open
                  },
                  onAssociateTag: () {
                    // Navigate to tag association screen
                    context.push('/library/album/$selectedAlbumId/tag');
                  },
                )
              : const LibraryScreen(),
        ),
      ],
    );
  }
}

/// Helper function to handle album tap on tablets.
///
/// On tablets in landscape, this opens the album in the detail panel.
/// On phones or tablets in portrait, this navigates to the full detail screen.
void handleAlbumTap(
  BuildContext context,
  WidgetRef ref,
  String albumId,
) {
  if (AdaptiveLayout.shouldShowDualPane(context)) {
    // On tablet landscape, show in panel
    ref.read(tabletSelectedAlbumIdProvider.notifier).state = albumId;
  } else {
    // On phone or tablet portrait, navigate to full screen
    context.push('${RoutePaths.library}/album/$albumId');
  }
}
