import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/suppliers_provider.dart';
import 'package:saturday_app/screens/parts/scan_receive_screen.dart';
import 'package:saturday_app/services/supabase_service.dart';

class ReceiveInventoryScreen extends ConsumerStatefulWidget {
  /// If provided, pre-selects the part.
  final String? partId;

  const ReceiveInventoryScreen({super.key, this.partId});

  @override
  ConsumerState<ReceiveInventoryScreen> createState() =>
      _ReceiveInventoryScreenState();
}

class _ReceiveInventoryScreenState
    extends ConsumerState<ReceiveInventoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _referenceController = TextEditingController();
  final _searchController = TextEditingController();

  String? _selectedPartId;
  String? _selectedSupplierId;
  String _searchQuery = '';
  bool _isSubmitting = false;
  bool _submitted = false;
  double? _newStockLevel;

  @override
  void initState() {
    super.initState();
    _selectedPartId = widget.partId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _referenceController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Inventory'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            label: const Text('Scan Mode',
                style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ScanReceiveScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _submitted ? _buildSuccessView() : _buildForm(),
    );
  }

  Widget _buildSuccessView() {
    final partsAsync = ref.watch(partsListProvider);
    final selectedPart = partsAsync.valueOrNull
        ?.where((p) => p.id == _selectedPartId)
        .firstOrNull;

    return Center(
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  size: 64, color: SaturdayColors.success),
              const SizedBox(height: 16),
              const Text('Inventory Received',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (selectedPart != null) ...[
                Text(selectedPart.name,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  'New stock level: ${_newStockLevel != null ? (_newStockLevel! % 1 == 0 ? _newStockLevel!.toInt() : _newStockLevel!.toStringAsFixed(2)) : '—'} ${selectedPart.unitOfMeasure.displayName}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SaturdayColors.success),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      // If embedded as a tab, reset to form; if pushed as a route, pop
                      if (Navigator.of(context).canPop()) {
                        Navigator.pop(context, true);
                      } else {
                        setState(() {
                          _submitted = false;
                          _quantityController.clear();
                          _referenceController.clear();
                          _selectedSupplierId = null;
                          _selectedPartId = widget.partId;
                        });
                      }
                    },
                    child: const Text('Done'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => setState(() {
                      _submitted = false;
                      _quantityController.clear();
                      _referenceController.clear();
                      _selectedSupplierId = null;
                      _selectedPartId = null;
                    }),
                    child: const Text('Receive Another'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final partsAsync = _searchQuery.isNotEmpty
        ? ref.watch(partSearchProvider(_searchQuery))
        : ref.watch(partsListProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Part selection
            const Text('Part *',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_selectedPartId != null) ...[
              _SelectedPartCard(
                partId: _selectedPartId!,
                onClear: () => setState(() => _selectedPartId = null),
              ),
            ] else ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search for a part...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              if (_searchQuery.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: partsAsync.when(
                    data: (parts) {
                      if (parts.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No parts found',
                              style: TextStyle(
                                  color: SaturdayColors.secondaryGrey)),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: parts.length,
                        itemBuilder: (context, index) {
                          final part = parts[index];
                          return ListTile(
                            dense: true,
                            title: Text(part.name),
                            subtitle: Text(part.partNumber),
                            onTap: () {
                              setState(() {
                                _selectedPartId = part.id;
                                _searchQuery = '';
                                _searchController.clear();
                              });
                            },
                          );
                        },
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                          child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Error: $e'),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),

            // Quantity
            TextFormField(
              controller: _quantityController,
              decoration: const InputDecoration(
                labelText: 'Quantity *',
                hintText: 'Amount received',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Quantity is required';
                final qty = double.tryParse(v);
                if (qty == null || qty <= 0) return 'Enter a positive number';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Supplier (optional)
            suppliersAsync.when(
              data: (suppliers) {
                if (suppliers.isEmpty) return const SizedBox.shrink();
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Supplier (optional)',
                  ),
                  initialValue: _selectedSupplierId,
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('None')),
                    ...suppliers.map((s) => DropdownMenuItem(
                        value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedSupplierId = v),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // Reference
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                hintText: 'PO#, packing slip, etc.',
              ),
            ),
            const SizedBox(height: 24),

            // Submit
            FilledButton(
              onPressed:
                  _isSubmitting || _selectedPartId == null ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Receive Inventory'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPartId == null) return;

    setState(() => _isSubmitting = true);

    try {
      final userId =
          SupabaseService.instance.client.auth.currentUser!.id;
      final management = ref.read(inventoryManagementProvider);

      await management.receive(
        partId: _selectedPartId!,
        quantity: double.parse(_quantityController.text),
        supplierId: _selectedSupplierId,
        reference: _referenceController.text.isNotEmpty
            ? _referenceController.text
            : null,
        performedBy: userId,
      );

      // Fetch updated stock level
      final newLevel = await ref
          .read(inventoryRepositoryProvider)
          .getInventoryLevel(_selectedPartId!);

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitted = true;
          _newStockLevel = newLevel;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: SaturdayColors.error),
        );
      }
    }
  }
}

class _SelectedPartCard extends ConsumerWidget {
  final String partId;
  final VoidCallback onClear;

  const _SelectedPartCard({required this.partId, required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partAsync = ref.watch(partDetailProvider(partId));
    final stockAsync = ref.watch(inventoryLevelProvider(partId));

    return partAsync.when(
      data: (part) {
        if (part == null) return const SizedBox.shrink();
        final stock = stockAsync.valueOrNull ?? 0.0;
        return Card(
          child: ListTile(
            title: Text(part.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${part.partNumber}  |  Current stock: ${stock % 1 == 0 ? stock.toInt() : stock.toStringAsFixed(2)} ${part.unitOfMeasure.displayName}'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
          ),
        );
      },
      loading: () => const Card(
        child: ListTile(
          title: Text('Loading...'),
        ),
      ),
      error: (e, _) => Card(
        child: ListTile(
          title: Text('Error: $e'),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClear,
          ),
        ),
      ),
    );
  }
}
