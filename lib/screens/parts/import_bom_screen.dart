import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/sub_assembly_provider.dart';
import 'package:saturday_app/repositories/parts_repository.dart';
import 'package:saturday_app/repositories/sub_assembly_repository.dart';
import 'package:saturday_app/repositories/supplier_parts_repository.dart';
import 'package:saturday_app/services/eaglecad_bom_parser.dart';

/// Import an EagleCAD BOM CSV into a sub-assembly's component list.
class ImportBomScreen extends ConsumerStatefulWidget {
  final String parentPartId;
  final String parentPartName;

  const ImportBomScreen({
    super.key,
    required this.parentPartId,
    required this.parentPartName,
  });

  @override
  ConsumerState<ImportBomScreen> createState() => _ImportBomScreenState();
}

enum _ImportStep { upload, review, importing, done }

class _ImportBomScreenState extends ConsumerState<ImportBomScreen> {
  final _parser = EaglecadBomParser();
  final _pasteController = TextEditingController();

  _ImportStep _step = _ImportStep.upload;
  List<ParsedBomEntry> _entries = [];
  List<_ReconciliationRow> _rows = [];
  int _created = 0;
  int _updated = 0;
  int _removed = 0;
  int _unchanged = 0;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Import BOM — ${widget.parentPartName}'),
      ),
      body: switch (_step) {
        _ImportStep.upload => _buildUploadStep(),
        _ImportStep.review => _buildReviewStep(),
        _ImportStep.importing => _buildImportingStep(),
        _ImportStep.done => _buildDoneStep(),
      },
    );
  }

  Widget _buildUploadStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Upload or paste an EagleCAD BOM CSV file.',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Expected columns: Qty, Value, Package, Parts (reference designators). '
            'Optional: LCSC_PART, DIGIKEY_PART, MOUSER_PART for supplier matching.',
            style: TextStyle(color: SaturdayColors.secondaryGrey),
          ),
          const SizedBox(height: 24),

          // File upload
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Choose CSV File'),
            onPressed: _pickFile,
          ),
          const SizedBox(height: 24),

          // Or paste
          const Text('Or paste CSV content:',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _pasteController,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: 'Qty;Value;Device;Package;Parts\n1;100nF;C0402;C0402;C1',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _pasteController.text.trim().isNotEmpty
                ? () => _parseBom(_pasteController.text)
                : null,
            child: const Text('Parse & Review'),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final hasChanges = _rows.any((r) => r.action != _Action.unchanged);

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.all(12),
          color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
          child: Row(
            children: [
              _SummaryChip(
                  label: 'New',
                  count: _rows.where((r) => r.action == _Action.create).length,
                  color: SaturdayColors.success),
              const SizedBox(width: 8),
              _SummaryChip(
                  label: 'Updated',
                  count: _rows.where((r) => r.action == _Action.update).length,
                  color: Colors.orange),
              const SizedBox(width: 8),
              _SummaryChip(
                  label: 'Removed',
                  count: _rows.where((r) => r.action == _Action.remove).length,
                  color: SaturdayColors.error),
              const SizedBox(width: 8),
              _SummaryChip(
                  label: 'Unchanged',
                  count:
                      _rows.where((r) => r.action == _Action.unchanged).length,
                  color: SaturdayColors.secondaryGrey),
              const Spacer(),
              OutlinedButton(
                onPressed: () => setState(() => _step = _ImportStep.upload),
                child: const Text('Back'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: hasChanges ? _executeImport : null,
                child: const Text('Apply Changes'),
              ),
            ],
          ),
        ),

        // Reconciliation table
        Expanded(
          child: _rows.isEmpty
              ? const Center(child: Text('No entries parsed'))
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    return _ReconciliationTile(row: row);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildImportingStep() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Applying BOM changes...'),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
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
              const Text('Import Complete',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (_created > 0)
                Text('$_created new components created',
                    style: const TextStyle(color: SaturdayColors.success)),
              if (_updated > 0)
                Text('$_updated components updated',
                    style: const TextStyle(color: Colors.orange)),
              if (_removed > 0)
                Text('$_removed components removed',
                    style: const TextStyle(color: SaturdayColors.error)),
              if (_unchanged > 0)
                Text('$_unchanged unchanged',
                    style:
                        const TextStyle(color: SaturdayColors.secondaryGrey)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Logic ----

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final content = await File(result.files.single.path!).readAsString();
      _parseBom(content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to read file: $e'),
              backgroundColor: SaturdayColors.error),
        );
      }
    }
  }

  void _parseBom(String content) {
    final entries = _parser.parseCsv(content);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No valid BOM entries found in file'),
            backgroundColor: SaturdayColors.warning),
      );
      return;
    }

    setState(() {
      _entries = entries;
    });

    _reconcile();
  }

  void _reconcile() {
    final allParts = ref.read(partsListProvider).valueOrNull ?? [];
    final existingLines =
        ref.read(subAssemblyLinesProvider(widget.parentPartId)).valueOrNull ??
            [];

    final rows = <_ReconciliationRow>[];
    final matchedExistingIds = <String>{};

    for (final entry in _entries) {
      // Try to match to existing part by supplier SKU or name
      Part? matchedPart;

      // Match by name or part number
      matchedPart = allParts.where((p) {
        final nameMatch =
            p.name.toLowerCase() == entry.suggestedPartName.toLowerCase();
        final numberMatch =
            p.partNumber.toLowerCase() ==
            entry.suggestedPartNumber.toLowerCase();
        return nameMatch || numberMatch;
      }).firstOrNull;

      // Check if existing sub_assembly_line exists
      final existingLine = matchedPart != null
          ? existingLines
              .where((l) => l.childPartId == matchedPart!.id)
              .firstOrNull
          : null;

      if (existingLine != null) {
        matchedExistingIds.add(existingLine.id);
        final qtyChanged = existingLine.quantity != entry.quantity.toDouble();
        rows.add(_ReconciliationRow(
          entry: entry,
          matchedPart: matchedPart,
          existingLineId: existingLine.id,
          action: qtyChanged ? _Action.update : _Action.unchanged,
        ));
      } else if (matchedPart != null) {
        rows.add(_ReconciliationRow(
          entry: entry,
          matchedPart: matchedPart,
          action: _Action.update,
        ));
      } else {
        rows.add(_ReconciliationRow(
          entry: entry,
          action: _Action.create,
        ));
      }
    }

    // Find lines that will be removed (exist but not in new BOM)
    for (final line in existingLines) {
      if (!matchedExistingIds.contains(line.id)) {
        final part =
            allParts.where((p) => p.id == line.childPartId).firstOrNull;
        rows.add(_ReconciliationRow(
          entry: ParsedBomEntry(
            referenceDesignator: line.referenceDesignator ?? '—',
            value: part?.name ?? 'Unknown',
            package: '',
            quantity: line.quantity.toInt(),
          ),
          matchedPart: part,
          existingLineId: line.id,
          action: _Action.remove,
        ));
      }
    }

    setState(() {
      _rows = rows;
      _step = _ImportStep.review;
    });
  }

  Future<void> _executeImport() async {
    setState(() => _step = _ImportStep.importing);

    final partsRepo = PartsRepository();
    final subAssemblyRepo = SubAssemblyRepository();
    final supplierPartsRepo = SupplierPartsRepository();

    int created = 0, updated = 0, removed = 0, unchanged = 0;

    try {
      for (final row in _rows) {
        switch (row.action) {
          case _Action.create:
            // Create the part
            final newPart = await partsRepo.createPart(
              name: row.entry.suggestedPartName,
              partNumber: row.entry.suggestedPartNumber,
              partType: PartType.component,
              category: PartCategory.electronics,
              unitOfMeasure: UnitOfMeasure.each,
            );

            // Create supplier part links
            for (final sp in row.entry.supplierParts.entries) {
              try {
                // Find or skip supplier (we create supplier_parts without a supplier for now)
                // In future, could auto-create suppliers
                await supplierPartsRepo.createSupplierPart(
                  partId: newPart.id,
                  supplierId: newPart.id, // placeholder — will need real supplier
                  supplierSku: sp.value,
                );
              } catch (_) {
                // Skip supplier link failures
              }
            }

            // Create sub_assembly_line
            await subAssemblyRepo.createSubAssemblyLine(
              parentPartId: widget.parentPartId,
              childPartId: newPart.id,
              quantity: row.entry.quantity.toDouble(),
              referenceDesignator: row.entry.referenceDesignator != '—'
                  ? row.entry.referenceDesignator
                  : null,
            );
            created++;

          case _Action.update:
            if (row.existingLineId != null) {
              await subAssemblyRepo.updateSubAssemblyLine(
                row.existingLineId!,
                quantity: row.entry.quantity.toDouble(),
                referenceDesignator: row.entry.referenceDesignator != '—'
                    ? row.entry.referenceDesignator
                    : null,
              );
            } else if (row.matchedPart != null) {
              await subAssemblyRepo.createSubAssemblyLine(
                parentPartId: widget.parentPartId,
                childPartId: row.matchedPart!.id,
                quantity: row.entry.quantity.toDouble(),
                referenceDesignator: row.entry.referenceDesignator != '—'
                    ? row.entry.referenceDesignator
                    : null,
              );
            }
            updated++;

          case _Action.remove:
            if (row.existingLineId != null) {
              await subAssemblyRepo.deleteSubAssemblyLine(row.existingLineId!);
            }
            removed++;

          case _Action.unchanged:
            unchanged++;
        }
      }

      // Invalidate providers
      ref.invalidate(partsListProvider);
      ref.invalidate(subAssemblyLinesProvider(widget.parentPartId));

      if (mounted) {
        setState(() {
          _created = created;
          _updated = updated;
          _removed = removed;
          _unchanged = unchanged;
          _step = _ImportStep.done;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Import failed: $e'),
              backgroundColor: SaturdayColors.error),
        );
        setState(() => _step = _ImportStep.review);
      }
    }
  }
}

enum _Action { create, update, remove, unchanged }

class _ReconciliationRow {
  final ParsedBomEntry entry;
  final Part? matchedPart;
  final String? existingLineId;
  final _Action action;

  _ReconciliationRow({
    required this.entry,
    this.matchedPart,
    this.existingLineId,
    required this.action,
  });
}

class _ReconciliationTile extends StatelessWidget {
  final _ReconciliationRow row;
  const _ReconciliationTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (row.action) {
      _Action.create => (Icons.add_circle, SaturdayColors.success, 'NEW'),
      _Action.update => (Icons.edit, Colors.orange, 'UPDATE'),
      _Action.remove => (Icons.remove_circle, SaturdayColors.error, 'REMOVE'),
      _Action.unchanged =>
        (Icons.check_circle, SaturdayColors.secondaryGrey, 'OK'),
    };

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        row.matchedPart?.name ?? row.entry.suggestedPartName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration:
              row.action == _Action.remove ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '${row.entry.referenceDesignator}  •  Qty: ${row.entry.quantity}'
        '${row.entry.supplierParts.isNotEmpty ? '  •  ${row.entry.supplierParts.entries.map((e) => "${e.key}: ${e.value}").join(", ")}' : ''}',
      ),
      trailing: Chip(
        label: Text(label, style: TextStyle(color: color, fontSize: 11)),
        backgroundColor: color.withValues(alpha: 0.1),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Text('$count',
          style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}
