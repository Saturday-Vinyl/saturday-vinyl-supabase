import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';

/// Now Playing screen - shows the currently playing record.
///
/// This is the primary entry point for the app, displaying:
/// - Album art with spinning animation when playing
/// - Album metadata (title, artist, year)
/// - Playback progress indicator
/// - What's next queue
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SaturdayAppBar(
        showLibrarySwitcher: true,
        showSearch: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: Spacing.pagePadding,
          child: Column(
            children: [
              // Album art placeholder
              Expanded(
                flex: 3,
                child: Container(
                  decoration: AppDecorations.albumArt,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.album, size: 80),
                        SizedBox(height: 16),
                        Text('No record playing'),
                        SizedBox(height: 8),
                        Text(
                          'Place a record on your turntable to get started',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Spacing.sectionGap,

              // Album info placeholder
              Expanded(
                flex: 1,
                child: Container(
                  decoration: AppDecorations.card,
                  padding: Spacing.cardPadding,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What\'s Next',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Your recently played albums will appear here',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
