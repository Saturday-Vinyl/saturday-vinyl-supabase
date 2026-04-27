import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/models/cratelist.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// Modal bottom sheet to create a new cratelist by name.
///
/// Returns the created [Cratelist] via Navigator.pop, or null if cancelled.
class CreateCratelistSheet extends ConsumerStatefulWidget {
  const CreateCratelistSheet({super.key});

  static Future<Cratelist?> show(BuildContext context) {
    return showModalBottomSheet<Cratelist>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CreateCratelistSheet(),
    );
  }

  @override
  ConsumerState<CreateCratelistSheet> createState() =>
      _CreateCratelistSheetState();
}

class _CreateCratelistSheetState extends ConsumerState<CreateCratelistSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to create cratelists')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final cratelist = await ref
          .read(cratelistRepositoryProvider)
          .createCratelist(name: name, userId: userId);
      ref.invalidate(userCratelistsProvider);
      ref.invalidate(cratelistPreviewsProvider);
      if (mounted) Navigator.pop(context, cratelist);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create cratelist: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New cratelist',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Spacing.lg),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Sunday morning',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_submitting ||
                              _controller.text.trim().isEmpty)
                          ? null
                          : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
