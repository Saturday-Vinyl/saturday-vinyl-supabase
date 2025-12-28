import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// Custom app bar for the Saturday app.
///
/// Features:
/// - Optional library switcher dropdown
/// - Optional search button
/// - Consistent Saturday branding
class SaturdayAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showLibrarySwitcher;
  final bool showSearch;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const SaturdayAppBar({
    super.key,
    this.title,
    this.showLibrarySwitcher = false,
    this.showSearch = false,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      title: showLibrarySwitcher
          ? const _LibrarySwitcher()
          : (title != null ? Text(title!) : null),
      actions: [
        if (showSearch)
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: () {
              context.push(RoutePaths.search);
            },
          ),
        if (actions != null) ...actions!,
        const SizedBox(width: 8),
      ],
    );
  }
}

/// Library switcher dropdown in the app bar.
class _LibrarySwitcher extends StatelessWidget {
  const _LibrarySwitcher();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _showLibrarySwitcher(context);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'My Library',
            style: Theme.of(context).appBarTheme.titleTextStyle,
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 24),
        ],
      ),
    );
  }

  void _showLibrarySwitcher(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _LibrarySwitcherSheet(),
    );
  }
}

/// Bottom sheet for switching between libraries.
class _LibrarySwitcherSheet extends StatelessWidget {
  const _LibrarySwitcherSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Switch Library',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),

          // Current library
          ListTile(
            leading: const Icon(Icons.library_music),
            title: const Text('My Library'),
            subtitle: const Text('12 albums'),
            trailing: const Icon(Icons.check, color: SaturdayColors.success),
            onTap: () {
              Navigator.pop(context);
            },
          ),

          const Divider(height: 1),

          // Shared libraries placeholder
          ListTile(
            leading: Icon(
              Icons.share,
              color: SaturdayColors.secondary,
            ),
            title: Text(
              'Shared Libraries',
              style: TextStyle(color: SaturdayColors.secondary),
            ),
            subtitle: Text(
              'No shared libraries yet',
              style: TextStyle(color: SaturdayColors.secondary),
            ),
            onTap: null,
          ),

          const Divider(height: 1),

          // Create new library
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Create New Library'),
            onTap: () {
              Navigator.pop(context);
              // TODO: Navigate to create library
            },
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
