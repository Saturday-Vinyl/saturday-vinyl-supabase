import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/widgets/common/animated_illustration.dart';

/// Screen shown after library creation to introduce adding albums.
///
/// Explains the different ways to add albums and encourages the user
/// to add their first album.
class AddAlbumIntroScreen extends ConsumerWidget {
  const AddAlbumIntroScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLibrary = ref.watch(currentLibraryProvider);
    final libraryName = currentLibrary?.name ?? 'your library';
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: SaturdayColors.light,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Spacing.pagePadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom -
                  Spacing.pagePadding.vertical,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: Spacing.xxl),

                // Success animation
                const AnimatedIllustration(
                  type: IllustrationType.libraryCreated,
                  size: 140,
                ),

                const SizedBox(height: Spacing.xl),

                // Success message
                Text(
                  'Library Created!',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: Spacing.sm),

                Text(
                  '"$libraryName" is ready for your vinyl.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: SaturdayColors.secondary,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: Spacing.xxl),

                // Add album intro illustration
                const AnimatedIllustration(
                  type: IllustrationType.addAlbumIntro,
                  size: 160,
                ),

                const SizedBox(height: Spacing.xl),

                // Explanation
                Text(
                  'Add Your First Album',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: Spacing.md),

                // Methods explanation
                _buildMethodCard(
                  context,
                  icon: Icons.qr_code_scanner,
                  title: 'Scan Barcode',
                  description: 'Point your camera at the album barcode for instant lookup.',
                ),

                const SizedBox(height: Spacing.sm),

                _buildMethodCard(
                  context,
                  icon: Icons.camera_alt,
                  title: 'Photo Recognition',
                  description: 'Take a photo of the album cover to identify it.',
                ),

                const SizedBox(height: Spacing.sm),

                _buildMethodCard(
                  context,
                  icon: Icons.search,
                  title: 'Manual Search',
                  description: 'Search by artist, album title, or catalog number.',
                ),

                const SizedBox(height: Spacing.xxl),

                // Continue button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _continueToAddAlbum(context),
                    child: const Text('Add Your First Album'),
                  ),
                ),

                const SizedBox(height: Spacing.md),

                // Skip for now link
                TextButton(
                  onPressed: () => _skipToLibrary(context),
                  child: Text(
                    'I\'ll do this later',
                    style: TextStyle(
                      color: SaturdayColors.secondary,
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SaturdayColors.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: SaturdayColors.primaryDark,
              size: 22,
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _continueToAddAlbum(BuildContext context) {
    // Navigate to library and show add album bottom sheet
    context.go('/library');
    // We need a slight delay to ensure the library screen is mounted
    Future.delayed(const Duration(milliseconds: 300), () {
      _showAddAlbumMenu(context);
    });
  }

  void _skipToLibrary(BuildContext context) {
    context.go('/library');
  }

  /// Show the add album menu with camera and manual entry options.
  void _showAddAlbumMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                'Add Album',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: SaturdayColors.primaryDark,
                ),
              ),
              title: const Text('Use Camera'),
              subtitle: const Text(
                'Scan barcode or photograph album cover',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/add/scan');
              },
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.search,
                  color: SaturdayColors.primaryDark,
                ),
              ),
              title: const Text('Manual Entry'),
              subtitle: const Text(
                'Search by artist, album, or catalog number',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/add/search');
              },
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
    );
  }
}
