import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/rfid_tag_roll_provider.dart';
import 'package:saturday_app/screens/rolls/roll_write_screen.dart';

/// Screen for creating a new RFID tag roll
class CreateRollScreen extends ConsumerStatefulWidget {
  const CreateRollScreen({super.key});

  @override
  ConsumerState<CreateRollScreen> createState() => _CreateRollScreenState();
}

class _CreateRollScreenState extends ConsumerState<CreateRollScreen> {
  final _formKey = GlobalKey<FormState>();
  final _widthController = TextEditingController(text: '25');
  final _heightController = TextEditingController(text: '25');
  final _countController = TextEditingController(text: '100');
  final _urlController = TextEditingController();

  bool _isCreating = false;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _countController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Roll'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SaturdayColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SaturdayColors.info),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: SaturdayColors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enter the specifications for your RFID tag roll. '
                        'After creating the roll, you can start writing tags.',
                        style: TextStyle(color: SaturdayColors.primaryDark),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Label dimensions section
              Text(
                'Label Dimensions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  // Width field
                  Expanded(
                    child: TextFormField(
                      controller: _widthController,
                      decoration: const InputDecoration(
                        labelText: 'Width (mm)',
                        hintText: '25',
                        suffixText: 'mm',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      validator: _validateDimension,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Height field
                  Expanded(
                    child: TextFormField(
                      controller: _heightController,
                      decoration: const InputDecoration(
                        labelText: 'Height (mm)',
                        hintText: '25',
                        suffixText: 'mm',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      validator: _validateDimension,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Label count section
              Text(
                'Roll Details',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _countController,
                decoration: const InputDecoration(
                  labelText: 'Total Labels on Roll',
                  hintText: '100',
                  helperText: 'How many labels are on this roll?',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: _validateCount,
              ),

              const SizedBox(height: 16),

              // Manufacturer URL (optional)
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Manufacturer URL (optional)',
                  hintText: 'https://...',
                  helperText: 'Link to the product page for this roll',
                ),
                keyboardType: TextInputType.url,
              ),

              const SizedBox(height: 32),

              // Common roll presets
              Text(
                'Quick Presets',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PresetChip(
                    label: '25x25mm (100)',
                    onTap: () => _applyPreset(25, 25, 100),
                  ),
                  _PresetChip(
                    label: '30x20mm (200)',
                    onTap: () => _applyPreset(30, 20, 200),
                  ),
                  _PresetChip(
                    label: '40x30mm (100)',
                    onTap: () => _applyPreset(40, 30, 100),
                  ),
                  _PresetChip(
                    label: '50x50mm (50)',
                    onTap: () => _applyPreset(50, 50, 50),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Create button
              FilledButton.icon(
                onPressed: _isCreating ? null : _createRoll,
                icon: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add),
                label: Text(_isCreating ? 'Creating...' : 'Create Roll'),
                style: FilledButton.styleFrom(
                  backgroundColor: SaturdayColors.primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validateDimension(String? value) {
    if (value == null || value.isEmpty) {
      return 'Required';
    }
    final number = double.tryParse(value);
    if (number == null) {
      return 'Invalid number';
    }
    if (number <= 0) {
      return 'Must be positive';
    }
    if (number < 5) {
      return 'Minimum 5mm';
    }
    if (number > 200) {
      return 'Maximum 200mm';
    }
    return null;
  }

  String? _validateCount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Required';
    }
    final number = int.tryParse(value);
    if (number == null) {
      return 'Invalid number';
    }
    if (number <= 0) {
      return 'Must be positive';
    }
    if (number > 10000) {
      return 'Maximum 10,000 labels';
    }
    return null;
  }

  void _applyPreset(double width, double height, int count) {
    _widthController.text = width.toStringAsFixed(0);
    _heightController.text = height.toStringAsFixed(0);
    _countController.text = count.toString();
  }

  Future<void> _createRoll() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final width = double.parse(_widthController.text);
      final height = double.parse(_heightController.text);
      final count = int.parse(_countController.text);
      final url = _urlController.text.isEmpty ? null : _urlController.text;

      final user = await ref.read(currentUserProvider.future);
      final management = ref.read(rfidTagRollManagementProvider);

      final roll = await management.createRoll(
        labelWidthMm: width,
        labelHeightMm: height,
        labelCount: count,
        manufacturerUrl: url,
        createdBy: user?.id,
      );

      if (mounted) {
        // Navigate to write screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RollWriteScreen(rollId: roll.id),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create roll: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }
}

/// Chip widget for preset values
class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: SaturdayColors.light,
    );
  }
}
