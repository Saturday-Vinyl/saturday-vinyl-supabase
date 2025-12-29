import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// Screen for creating a new library.
class CreateLibraryScreen extends ConsumerStatefulWidget {
  const CreateLibraryScreen({super.key});

  @override
  ConsumerState<CreateLibraryScreen> createState() =>
      _CreateLibraryScreenState();
}

class _CreateLibraryScreenState extends ConsumerState<CreateLibraryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createLibrary() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      setState(() => _error = 'Not signed in');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final libraryRepo = ref.read(libraryRepositoryProvider);
      final library = await libraryRepo.createLibrary(
        _nameController.text.trim(),
        userId,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      // Invalidate the libraries provider to refresh the list
      ref.invalidate(userLibrariesProvider);

      // Set the new library as current
      ref.read(currentLibraryIdProvider.notifier).state = library.id;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "${library.name}"')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to create library: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Library'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Spacing.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Spacing.lg),

                // Icon
                Icon(
                  Icons.library_music,
                  size: 64,
                  color: SaturdayColors.primaryDark,
                ),
                const SizedBox(height: Spacing.xl),

                // Name field
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Library Name',
                    hintText: 'e.g., My Vinyl Collection',
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    if (value.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: Spacing.lg),

                // Description field
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'A brief description of this library',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                ),
                const SizedBox(height: Spacing.xl),

                // Error message
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: SaturdayColors.error.withValues(alpha: 0.1),
                      borderRadius: AppRadius.mediumRadius,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: SaturdayColors.error),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: SaturdayColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                ],

                // Create button
                ElevatedButton(
                  onPressed: _isLoading ? null : _createLibrary,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Library'),
                ),
                const SizedBox(height: Spacing.xl),

                // Info text
                Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: SaturdayColors.info.withValues(alpha: 0.1),
                    borderRadius: AppRadius.mediumRadius,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: SaturdayColors.info),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          'You can invite others to view or edit this library later from the library settings.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
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
