import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';

/// Shows a bottom sheet to choose between QR code scanning and hub-based
/// tag association. If the user has no hubs, navigates directly to QR scanner.
void showTagMethodPicker(
  BuildContext context,
  WidgetRef ref,
  String libraryAlbumId,
) {
  final hubsAsync = ref.read(userHubsProvider);

  // If we know there are no hubs, go straight to QR
  final hubs = hubsAsync.valueOrNull;
  if (hubs != null && hubs.isEmpty) {
    context.push('/library/album/$libraryAlbumId/tag');
    return;
  }

  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Text(
              'How would you like to identify the tag?',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: 1),

          // Option: Scan QR Code
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Scan QR Code'),
            subtitle: const Text('Use your camera to scan the code on the tag'),
            onTap: () {
              Navigator.pop(context);
              context.push('/library/album/$libraryAlbumId/tag');
            },
          ),

          // Option: Use Hub
          ListTile(
            leading: const Icon(Icons.router_outlined),
            title: const Text('Use Your Hub'),
            subtitle:
                const Text('Place the tag on your hub to identify it'),
            onTap: () {
              Navigator.pop(context);
              context.push('/library/album/$libraryAlbumId/tag/hub');
            },
          ),

          const SizedBox(height: Spacing.md),
        ],
      ),
    ),
  );
}
