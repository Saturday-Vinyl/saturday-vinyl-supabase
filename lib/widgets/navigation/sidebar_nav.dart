import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/constants.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/widgets/common/user_avatar.dart';

class SidebarNav extends ConsumerWidget {
  final String currentRoute;
  final Function(String) onNavigate;

  const SidebarNav({
    super.key,
    required this.currentRoute,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final isAdminAsync = ref.watch(isAdminProvider);

    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: SaturdayColors.primaryDark,
        border: Border(
          right: BorderSide(
            color: SaturdayColors.secondaryGrey,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo and app name
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'S!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: SaturdayColors.primaryDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    AppConstants.appName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(
            color: SaturdayColors.secondaryGrey,
            height: 1,
          ),

          // Navigation items
          Expanded(
            child: isAdminAsync.when(
              data: (isAdmin) => ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildNavItem(
                    icon: Icons.dashboard,
                    label: 'Dashboard',
                    route: '/dashboard',
                    isSelected: currentRoute == '/dashboard',
                  ),
                  _buildNavItem(
                    icon: Icons.inventory_2,
                    label: 'Products',
                    route: '/products',
                    isSelected: currentRoute == '/products',
                  ),
                  _buildNavItem(
                    icon: Icons.devices_other,
                    label: 'Device Types',
                    route: '/device-types',
                    isSelected: currentRoute == '/device-types',
                  ),
                  _buildNavItem(
                    icon: Icons.qr_code,
                    label: 'Production Units',
                    route: '/production',
                    isSelected: currentRoute == '/production',
                  ),
                  _buildNavItem(
                    icon: Icons.memory,
                    label: 'Firmware',
                    route: '/firmware',
                    isSelected: currentRoute == '/firmware',
                  ),
                  if (isAdmin) ...[
                    const Divider(
                      color: SaturdayColors.secondaryGrey,
                      height: 24,
                      indent: 16,
                      endIndent: 16,
                    ),
                    _buildNavItem(
                      icon: Icons.people,
                      label: 'Users',
                      route: '/users',
                      isSelected: currentRoute == '/users',
                      isAdminOnly: true,
                    ),
                  ],
                  const Divider(
                    color: SaturdayColors.secondaryGrey,
                    height: 24,
                    indent: 16,
                    endIndent: 16,
                  ),
                  _buildNavItem(
                    icon: Icons.settings,
                    label: 'Settings',
                    route: '/settings',
                    isSelected: currentRoute == '/settings',
                  ),
                ],
              ),
              loading: () => const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          // User profile section
          currentUserAsync.when(
            data: (user) {
              if (user == null) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: SaturdayColors.secondaryGrey,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    UserAvatar(
                      displayName: user.fullName,
                      email: user.email,
                      size: AvatarSize.small,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.fullName ?? 'User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (user.isAdmin)
                            const Text(
                              'Administrator',
                              style: TextStyle(
                                color: SaturdayColors.light,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required String route,
    required bool isSelected,
    bool isAdminOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onNavigate(route),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : SaturdayColors.light,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : SaturdayColors.light,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (isAdminOnly)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: SaturdayColors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: SaturdayColors.success,
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'ADMIN',
                      style: TextStyle(
                        color: SaturdayColors.success,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
