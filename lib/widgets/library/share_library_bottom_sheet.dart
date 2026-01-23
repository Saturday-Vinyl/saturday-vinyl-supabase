import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/providers/invitation_provider.dart';

/// Bottom sheet for inviting members to share a library.
///
/// Features:
/// - Email input with validation
/// - Role selection (editor/viewer)
/// - Send invitation button
/// - Loading and error states
class ShareLibraryBottomSheet extends ConsumerStatefulWidget {
  final String libraryId;

  const ShareLibraryBottomSheet({
    super.key,
    required this.libraryId,
  });

  @override
  ConsumerState<ShareLibraryBottomSheet> createState() =>
      _ShareLibraryBottomSheetState();
}

class _ShareLibraryBottomSheetState
    extends ConsumerState<ShareLibraryBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  LibraryRole _selectedRole = LibraryRole.viewer;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: Spacing.pagePadding,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: SaturdayColors.secondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Text(
                'Share Library',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),

              const SizedBox(height: 8),

              Text(
                'Invite someone to access your library',
                style: TextStyle(color: SaturdayColors.secondary),
              ),

              const SizedBox(height: 24),

              // Email input
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Email address',
                  hintText: 'friend@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: _validateEmail,
                onFieldSubmitted: (_) => _sendInvitation(),
              ),

              const SizedBox(height: 16),

              // Role selection
              Text(
                'Permission level',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),

              const SizedBox(height: 8),

              _buildRoleOption(
                role: LibraryRole.viewer,
                title: 'Viewer',
                description: 'Can browse and play albums',
                icon: Icons.visibility_outlined,
              ),

              const SizedBox(height: 8),

              _buildRoleOption(
                role: LibraryRole.editor,
                title: 'Editor',
                description: 'Can add, edit, and remove albums',
                icon: Icons.edit_outlined,
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SaturdayColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: SaturdayColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: SaturdayColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Send button
              ElevatedButton(
                onPressed: _isLoading ? null : _sendInvitation,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send Invitation'),
              ),

              const SizedBox(height: 8),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleOption({
    required LibraryRole role,
    required String title,
    required String description,
    required IconData icon,
  }) {
    final isSelected = _selectedRole == role;

    return InkWell(
      onTap: () => setState(() => _selectedRole = role),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? SaturdayColors.primaryDark
                : SaturdayColors.secondary.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? SaturdayColors.primaryDark.withValues(alpha: 0.05)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? SaturdayColors.primaryDark.withValues(alpha: 0.1)
                    : SaturdayColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? SaturdayColors.primaryDark
                    : SaturdayColors.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isSelected ? SaturdayColors.primaryDark : null,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: SaturdayColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: SaturdayColors.primaryDark,
              ),
          ],
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter an email address';
    }

    // Basic email validation
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  Future<void> _sendInvitation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final invitation = await ref
          .read(invitationNotifierProvider.notifier)
          .sendInvitation(
            libraryId: widget.libraryId,
            email: _emailController.text.trim(),
            role: _selectedRole,
          );

      if (invitation != null && mounted) {
        // Refresh pending invitations
        ref.invalidate(libraryPendingInvitationsProvider(widget.libraryId));

        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Invitation sent to ${_emailController.text.trim()}',
            ),
          ),
        );
      } else if (mounted) {
        final errorState = ref.read(invitationNotifierProvider);
        setState(() {
          _error = errorState.error ?? 'Failed to send invitation';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }
}
