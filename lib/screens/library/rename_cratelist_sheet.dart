import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/models/cratelist.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// Modal bottom sheet to rename an existing cratelist. Returns the updated
/// [Cratelist], or null if cancelled.
class RenameCratelistSheet extends ConsumerStatefulWidget {
  const RenameCratelistSheet({super.key, required this.cratelist});

  final Cratelist cratelist;

  static Future<Cratelist?> show(BuildContext context, Cratelist cratelist) {
    return showModalBottomSheet<Cratelist>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RenameCratelistSheet(cratelist: cratelist),
    );
  }

  @override
  ConsumerState<RenameCratelistSheet> createState() =>
      _RenameCratelistSheetState();
}

class _RenameCratelistSheetState extends ConsumerState<RenameCratelistSheet> {
  late final TextEditingController _controller;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.cratelist.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || name == widget.cratelist.name) {
      Navigator.pop(context);
      return;
    }

    setState(() => _submitting = true);
    try {
      final updated = await ref
          .read(cratelistRepositoryProvider)
          .updateCratelist(id: widget.cratelist.id, name: name);
      ref.invalidate(userCratelistsProvider);
      ref.invalidate(cratelistPreviewsProvider);
      ref.invalidate(cratelistByIdProvider(widget.cratelist.id));
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rename: $e')),
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
                'Rename cratelist',
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
                          : const Text('Save'),
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
