import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/user.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/users_provider.dart';
import 'package:saturday_app/screens/users/user_detail_screen.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/utils/extensions.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final allUsersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      backgroundColor: SaturdayColors.light,
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: currentUserAsync.when(
        data: (currentUser) {
          if (currentUser == null || !currentUser.isAdmin) {
            return _buildAccessDenied();
          }

          return allUsersAsync.when(
            data: (users) => _buildUsersList(users),
            loading: () => const LoadingIndicator(message: 'Loading users...'),
            error: (error, stack) => _buildError(error.toString()),
          );
        },
        loading: () => const LoadingIndicator(message: 'Loading...'),
        error: (error, stack) => _buildError(error.toString()),
      ),
    );
  }

  Widget _buildAccessDenied() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.block,
            size: 64,
            color: SaturdayColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Access Denied',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: SaturdayColors.primaryDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Only administrators can access user management.',
            style: TextStyle(color: SaturdayColors.secondaryGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: SaturdayColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SaturdayColors.secondaryGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList(List<User> users) {
    final filteredUsers = users.where((user) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return user.email.toLowerCase().contains(query) ||
          (user.fullName?.toLowerCase().contains(query) ?? false);
    }).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search users by name or email...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: SaturdayColors.secondaryGrey),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: SaturdayColors.secondaryGrey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: SaturdayColors.primaryDark, width: 2),
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),

        // User count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${filteredUsers.length} ${filteredUsers.length == 1 ? 'user' : 'users'}',
              style: const TextStyle(
                color: SaturdayColors.secondaryGrey,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Users list
        Expanded(
          child: filteredUsers.isEmpty
              ? const Center(
                  child: Text(
                    'No users found',
                    style: TextStyle(color: SaturdayColors.secondaryGrey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    return _buildUserCard(filteredUsers[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUserCard(User user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: SaturdayColors.secondaryGrey,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user.fullName ?? user.email,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: SaturdayColors.primaryDark,
                ),
              ),
            ),
            if (user.isAdmin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SaturdayColors.success,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'ADMIN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: user.isActive ? SaturdayColors.success : SaturdayColors.secondaryGrey,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              user.email,
              style: const TextStyle(
                fontSize: 14,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Joined ${user.createdAt.friendlyDate}',
              style: const TextStyle(
                fontSize: 12,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
          ],
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: SaturdayColors.secondaryGrey,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => UserDetailScreen(user: user),
            ),
          );
        },
      ),
    );
  }
}
