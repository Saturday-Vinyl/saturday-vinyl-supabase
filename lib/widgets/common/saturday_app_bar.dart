import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/widgets/common/library_switcher.dart';

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
          ? const LibrarySwitcherButton()
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
