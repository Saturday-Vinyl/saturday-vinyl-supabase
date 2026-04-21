import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/suppliers_provider.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

class SupplierFormScreen extends ConsumerStatefulWidget {
  final String? supplierId;

  const SupplierFormScreen({super.key, this.supplierId});

  @override
  ConsumerState<SupplierFormScreen> createState() =>
      _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _websiteController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;
  bool _initialized = false;

  bool get _isEditing => widget.supplierId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      final supplierAsync =
          ref.watch(supplierDetailProvider(widget.supplierId!));
      return supplierAsync.when(
        data: (supplier) {
          if (supplier == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Edit Supplier')),
              body: const Center(child: Text('Supplier not found')),
            );
          }
          if (!_initialized) {
            _initialized = true;
            _nameController.text = supplier.name;
            _websiteController.text = supplier.website ?? '';
            _notesController.text = supplier.notes ?? '';
          }
          return _buildForm();
        },
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('Edit Supplier')),
          body: const LoadingIndicator(message: 'Loading...'),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Edit Supplier')),
          body: Center(child: Text('Error: $e')),
        ),
      );
    }
    return _buildForm();
  }

  Widget _buildForm() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Supplier' : 'New Supplier'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g., Digikey, JLCPCB',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                  labelText: 'Website',
                  hintText: 'https://...',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Contact info, account numbers...',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Save Changes' : 'Create Supplier'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final management = ref.read(suppliersManagementProvider);

      if (_isEditing) {
        await management.updateSupplier(
          widget.supplierId!,
          name: _nameController.text,
          website: _websiteController.text.isNotEmpty
              ? _websiteController.text
              : null,
          notes: _notesController.text.isNotEmpty
              ? _notesController.text
              : null,
        );
      } else {
        await management.createSupplier(
          name: _nameController.text,
          website: _websiteController.text.isNotEmpty
              ? _websiteController.text
              : null,
          notes: _notesController.text.isNotEmpty
              ? _notesController.text
              : null,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isEditing ? 'Supplier updated' : 'Supplier created'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: SaturdayColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
