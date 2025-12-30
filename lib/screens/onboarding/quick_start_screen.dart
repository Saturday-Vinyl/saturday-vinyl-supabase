import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/widgets/common/animated_illustration.dart';

/// Quick start screen shown when user has no libraries.
///
/// Guides the user through creating their first library with a
/// friendly, welcoming experience.
class QuickStartScreen extends ConsumerStatefulWidget {
  const QuickStartScreen({super.key});

  @override
  ConsumerState<QuickStartScreen> createState() => _QuickStartScreenState();
}

class _QuickStartScreenState extends ConsumerState<QuickStartScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'My Collection');
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createLibrary() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      // Await the current user from the FutureProvider
      final user = await ref.read(currentUserProvider.future);
      if (user == null) {
        setState(() {
          _errorMessage = 'Please sign in to create a library';
          _isCreating = false;
        });
        return;
      }
      final userId = user.id;

      // Debug: log the user ID and auth UID
      final authUid = ref.read(currentSupabaseUserProvider)?.id;
      debugPrint('Creating library with userId: $userId, authUid: $authUid');

      final libraryRepo = ref.read(libraryRepositoryProvider);
      final newLibrary = await libraryRepo.createLibrary(
        _nameController.text.trim(),
        userId,
      );

      // Invalidate libraries to refresh the list
      ref.invalidate(userLibrariesProvider);

      // Set the new library as current
      ref.read(currentLibraryIdProvider.notifier).state = newLibrary.id;

      if (mounted) {
        // Navigate to the add album intro screen
        context.go('/onboarding/add-album-intro');
      }
    } catch (e) {
      debugPrint('Failed to create library: $e');
      setState(() {
        _errorMessage = 'Failed to create library: $e';
        _isCreating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SaturdayColors.light,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: Spacing.pagePadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: Spacing.xxl),

                // Animated vinyl illustration
                const AnimatedIllustration(
                  type: IllustrationType.welcomeVinyl,
                  size: 180,
                ),

                const SizedBox(height: Spacing.xxl),

                // Welcome text
                Text(
                  'Welcome to Saturday',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: Spacing.md),

                Text(
                  'Let\'s set up your first library to start\norganizing your vinyl collection.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: SaturdayColors.secondary,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: Spacing.xxl),

                // Library name form
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Library Name',
                      hintText: 'e.g., My Vinyl, Home Collection',
                    ),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a library name';
                      }
                      if (value.trim().length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      return null;
                    },
                  ),
                ),

                const SizedBox(height: Spacing.lg),

                // Hint text
                Container(
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: SaturdayColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: SaturdayColors.info.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: SaturdayColors.info,
                        size: 20,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          'You can create more libraries later for different locations or collections.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SaturdayColors.primaryDark,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: Spacing.md),
                  Container(
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: SaturdayColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: SaturdayColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: SaturdayColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: SaturdayColors.error,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: Spacing.xxl),

                // Get Started button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createLibrary,
                    child: _isCreating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Get Started'),
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
}
