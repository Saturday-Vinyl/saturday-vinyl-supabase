import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';

/// Library screen - shows the user's vinyl collection.
///
/// Features:
/// - Grid/list view toggle for albums
/// - Sort and filter options
/// - Quick search within library
/// - Add album via scanning or search
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SaturdayAppBar(
        showLibrarySwitcher: true,
        showSearch: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter/sort bar
            Padding(
              padding: Spacing.pageHorizontal,
              child: Row(
                children: [
                  // Sort button
                  TextButton.icon(
                    onPressed: () {
                      // TODO: Show sort options
                    },
                    icon: const Icon(Icons.sort, size: 20),
                    label: const Text('Recently Added'),
                  ),
                  const Spacer(),
                  // View toggle
                  IconButton(
                    onPressed: () {
                      // TODO: Toggle grid/list view
                    },
                    icon: const Icon(Icons.grid_view),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Empty state
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.album_outlined,
                      size: 80,
                      color: SaturdayColors.secondary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your library is empty',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add albums by scanning barcodes or\nsearching the Discogs catalog',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SaturdayColors.secondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Open scanner
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan Barcode'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Open search
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('Search Discogs'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Show add album options
        },
        tooltip: 'Add Album',
        child: const Icon(Icons.add),
      ),
    );
  }
}
