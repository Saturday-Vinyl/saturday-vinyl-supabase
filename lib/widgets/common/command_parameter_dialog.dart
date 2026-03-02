import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/capability.dart';

/// Dialog that generates form fields from a command's JSON Schema parameters.
///
/// Supports: string, string+enum, integer, and array of integer fields.
/// Pre-populates defaults and validates required fields.
class CommandParameterDialog extends StatefulWidget {
  final CapabilityCommand command;

  const CommandParameterDialog({super.key, required this.command});

  /// Show the dialog and return filled parameters, or null if cancelled.
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    required CapabilityCommand command,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => CommandParameterDialog(command: command),
    );
  }

  @override
  State<CommandParameterDialog> createState() => _CommandParameterDialogState();
}

class _CommandParameterDialogState extends State<CommandParameterDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _dropdownValues = {};

  late final Map<String, dynamic> _properties;
  late final List<String> _requiredFields;

  @override
  void initState() {
    super.initState();
    final schema = widget.command.parametersSchema;
    _properties =
        (schema['properties'] as Map<String, dynamic>?) ?? {};
    _requiredFields =
        (schema['required'] as List?)?.cast<String>() ?? [];

    for (final entry in _properties.entries) {
      final propSchema = entry.value as Map<String, dynamic>;
      final fieldType = _fieldType(propSchema);

      if (fieldType == _FieldType.enumDropdown) {
        final defaultVal = propSchema['default']?.toString();
        _dropdownValues[entry.key] = defaultVal;
      } else {
        final defaultVal = propSchema['default']?.toString() ?? '';
        _controllers[entry.key] = TextEditingController(text: defaultVal);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.command.displayName),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.command.description != null) ...[
                  Text(
                    widget.command.description!,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                ],
                ..._properties.entries.map(_buildField),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: SaturdayColors.primaryDark,
            foregroundColor: Colors.white,
          ),
          child: const Text('Run Command'),
        ),
      ],
    );
  }

  Widget _buildField(MapEntry<String, dynamic> entry) {
    final name = entry.key;
    final propSchema = entry.value as Map<String, dynamic>;
    final isRequired = _requiredFields.contains(name);
    final description = propSchema['description'] as String?;
    final fieldType = _fieldType(propSchema);

    final label = '${_formatLabel(name)}${isRequired ? ' *' : ''}';

    Widget field;
    switch (fieldType) {
      case _FieldType.enumDropdown:
        final enumValues =
            (propSchema['enum'] as List).map((e) => e.toString()).toList();
        field = DropdownButtonFormField<String>(
          initialValue: _dropdownValues[name],
          decoration: InputDecoration(
            labelText: label,
            helperText: description,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: enumValues
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) => setState(() => _dropdownValues[name] = v),
          validator: isRequired
              ? (v) => v == null || v.isEmpty ? 'Required' : null
              : null,
        );

      case _FieldType.integer:
        field = TextFormField(
          controller: _controllers[name],
          decoration: InputDecoration(
            labelText: label,
            helperText: description,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d-]'))],
          validator: (v) {
            if (isRequired && (v == null || v.isEmpty)) return 'Required';
            if (v != null && v.isNotEmpty && int.tryParse(v) == null) {
              return 'Must be a number';
            }
            return null;
          },
        );

      case _FieldType.intArray:
        field = TextFormField(
          controller: _controllers[name],
          decoration: InputDecoration(
            labelText: label,
            helperText: description ?? 'Comma-separated integers (e.g., 1, 2, 3)',
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          validator: (v) {
            if (isRequired && (v == null || v.isEmpty)) return 'Required';
            if (v != null && v.isNotEmpty) {
              final parts = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
              if (parts.any((s) => int.tryParse(s) == null)) {
                return 'Must be comma-separated integers';
              }
            }
            return null;
          },
        );

      case _FieldType.string:
        field = TextFormField(
          controller: _controllers[name],
          decoration: InputDecoration(
            labelText: label,
            helperText: description,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          validator: isRequired
              ? (v) =>
                  v == null || v.isEmpty ? 'Required' : null
              : null,
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: field,
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final params = <String, dynamic>{};

    for (final entry in _properties.entries) {
      final name = entry.key;
      final propSchema = entry.value as Map<String, dynamic>;
      final fieldType = _fieldType(propSchema);

      switch (fieldType) {
        case _FieldType.enumDropdown:
          final value = _dropdownValues[name];
          if (value != null && value.isNotEmpty) {
            params[name] = value;
          }

        case _FieldType.integer:
          final text = _controllers[name]!.text.trim();
          if (text.isNotEmpty) {
            params[name] = int.parse(text);
          }

        case _FieldType.intArray:
          final text = _controllers[name]!.text.trim();
          if (text.isNotEmpty) {
            params[name] = text
                .split(',')
                .map((s) => int.parse(s.trim()))
                .toList();
          }

        case _FieldType.string:
          final text = _controllers[name]!.text.trim();
          if (text.isNotEmpty) {
            params[name] = text;
          }
      }
    }

    Navigator.of(context).pop(params);
  }

  static _FieldType _fieldType(Map<String, dynamic> propSchema) {
    final type = propSchema['type'] as String?;
    if (type == 'string' && propSchema.containsKey('enum')) {
      return _FieldType.enumDropdown;
    }
    if (type == 'integer') {
      return _FieldType.integer;
    }
    if (type == 'array') {
      return _FieldType.intArray;
    }
    return _FieldType.string;
  }

  static String _formatLabel(String name) {
    return name.replaceAll('_', ' ').replaceAllMapped(
      RegExp(r'(^|\s)\w'),
      (m) => m.group(0)!.toUpperCase(),
    );
  }
}

enum _FieldType { string, enumDropdown, integer, intArray }
