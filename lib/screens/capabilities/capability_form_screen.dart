import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/providers/capability_provider.dart';
import 'package:saturday_app/utils/cbor_size_estimator.dart';
import 'package:saturday_app/widgets/common/app_button.dart';
import 'package:saturday_app/widgets/common/cbor_size_indicator.dart';

/// Form screen for creating or editing a capability
class CapabilityFormScreen extends ConsumerStatefulWidget {
  final Capability? capability; // null for create, non-null for edit

  const CapabilityFormScreen({
    super.key,
    this.capability,
  });

  @override
  ConsumerState<CapabilityFormScreen> createState() =>
      _CapabilityFormScreenState();
}

class _CapabilityFormScreenState extends ConsumerState<CapabilityFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Schema properties (simplified as list of property definitions)
  List<SchemaProperty> _factoryInputProperties = [];
  List<SchemaProperty> _factoryOutputProperties = [];
  List<SchemaProperty> _consumerInputProperties = [];
  List<SchemaProperty> _consumerOutputProperties = [];
  List<SchemaProperty> _heartbeatProperties = [];

  // Commands
  List<CapabilityCommand> _commands = [];

  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.capability != null) {
      _nameController.text = widget.capability!.name;
      _displayNameController.text = widget.capability!.displayName;
      _descriptionController.text = widget.capability!.description ?? '';
      _isActive = widget.capability!.isActive;

      // Parse schemas
      _factoryInputProperties =
          _parseSchemaProperties(widget.capability!.factoryInputSchema);
      _factoryOutputProperties =
          _parseSchemaProperties(widget.capability!.factoryOutputSchema);
      _consumerInputProperties =
          _parseSchemaProperties(widget.capability!.consumerInputSchema);
      _consumerOutputProperties =
          _parseSchemaProperties(widget.capability!.consumerOutputSchema);
      _heartbeatProperties =
          _parseSchemaProperties(widget.capability!.heartbeatSchema);

      // Copy commands
      _commands = List.from(widget.capability!.commands);
    }
  }

  List<SchemaProperty> _parseSchemaProperties(Map<String, dynamic>? schema) {
    if (schema == null || schema.isEmpty) return [];

    final properties = schema['properties'] as Map<String, dynamic>?;
    if (properties == null) return [];

    final required =
        (schema['required'] as List<dynamic>?)?.cast<String>() ?? [];

    return properties.entries.map((entry) {
      final fieldSchema = entry.value as Map<String, dynamic>;
      final type = fieldSchema['type']?.toString() ?? 'string';

      // Recursively parse nested object properties
      List<SchemaProperty> children = [];
      if (type == 'object' && fieldSchema['properties'] != null) {
        children = _parseSchemaProperties(fieldSchema);
      }

      return SchemaProperty(
        name: entry.key,
        type: type,
        description: fieldSchema['description']?.toString(),
        isRequired: required.contains(entry.key),
        children: children,
        enumValues: (fieldSchema['enum'] as List<dynamic>?)
            ?.map((v) => v.toString())
            .toList(),
        minimum: _toNum(fieldSchema['minimum']),
        maximum: _toNum(fieldSchema['maximum']),
      );
    }).toList();
  }

  static num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  Map<String, dynamic> _buildSchema(List<SchemaProperty> properties) {
    if (properties.isEmpty) return {};

    final propsMap = <String, dynamic>{};
    final required = <String>[];

    for (final prop in properties) {
      final propSchema = <String, dynamic>{
        'type': prop.type,
        if (prop.description != null && prop.description!.isNotEmpty)
          'description': prop.description,
      };

      // Recursively build nested object properties
      if (prop.type == 'object' && prop.children.isNotEmpty) {
        final nestedSchema = _buildSchema(prop.children);
        if (nestedSchema['properties'] != null) {
          propSchema['properties'] = nestedSchema['properties'];
        }
        if (nestedSchema['required'] != null) {
          propSchema['required'] = nestedSchema['required'];
        }
      }

      if (prop.enumValues != null && prop.enumValues!.isNotEmpty) {
        propSchema['enum'] = _coerceEnumValues(prop.type, prop.enumValues!);
      }
      if (_typeSupportsRange(prop.type)) {
        if (prop.minimum != null) {
          propSchema['minimum'] = _coerceNumForType(prop.type, prop.minimum!);
        }
        if (prop.maximum != null) {
          propSchema['maximum'] = _coerceNumForType(prop.type, prop.maximum!);
        }
      }

      propsMap[prop.name] = propSchema;
      if (prop.isRequired) {
        required.add(prop.name);
      }
    }

    return {
      'type': 'object',
      'properties': propsMap,
      if (required.isNotEmpty) 'required': required,
    };
  }

  static bool _typeSupportsRange(String type) =>
      type == 'integer' || type == 'number';

  static bool _typeSupportsEnum(String type) =>
      type == 'string' || type == 'integer' || type == 'number';

  static List<dynamic> _coerceEnumValues(String type, List<String> values) {
    if (type == 'integer') {
      return values.map((v) => int.tryParse(v.trim()) ?? v).toList();
    }
    if (type == 'number') {
      return values.map((v) => num.tryParse(v.trim()) ?? v).toList();
    }
    return values.map((v) => v).toList();
  }

  static num _coerceNumForType(String type, num value) =>
      type == 'integer' ? value.toInt() : value;

  static String? _constraintsSummary(SchemaProperty prop) {
    final parts = <String>[];
    if (prop.enumValues != null && prop.enumValues!.isNotEmpty) {
      parts.add('enum: ${prop.enumValues!.join(', ')}');
    }
    if (prop.minimum != null || prop.maximum != null) {
      final min = prop.minimum?.toString() ?? '−∞';
      final max = prop.maximum?.toString() ?? '∞';
      parts.add('range: $min … $max');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.capability != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Capability' : 'Add Capability'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Basic Information Section
              _buildSectionHeader('Basic Information'),
              const SizedBox(height: 16),

              // Name field (machine-readable)
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (machine-readable) *',
                  hintText: 'e.g., record_tracking, audio_playback',
                  helperText: 'Use snake_case, no spaces',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value.trim())) {
                    return 'Use lowercase letters, numbers, and underscores only';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Display name field
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display Name *',
                  hintText: 'e.g., Record Tracking',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a display name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description field
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Brief description of what this capability does',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Factory Input Schema
              _buildSectionHeader('Factory Input Schema'),
              const SizedBox(height: 8),
              Text(
                'Data sent to device during factory provisioning (UART/WebSocket). Persists through consumer reset.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              _buildSchemaEditor(
                properties: _factoryInputProperties,
                onChanged: (props) =>
                    setState(() => _factoryInputProperties = props),
              ),
              const SizedBox(height: 24),

              // Factory Output Schema
              _buildSectionHeader('Factory Output Schema'),
              const SizedBox(height: 8),
              Text(
                'Data returned by device after factory provisioning',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              _buildSchemaEditor(
                properties: _factoryOutputProperties,
                onChanged: (props) =>
                    setState(() => _factoryOutputProperties = props),
              ),
              const SizedBox(height: 24),

              // Consumer Input Schema
              _buildSectionHeader('Consumer Input Schema'),
              const SizedBox(height: 8),
              Text(
                'Data sent to device during consumer provisioning (BLE). Drives BLE service generation. Wiped on consumer reset.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              _buildSchemaEditor(
                properties: _consumerInputProperties,
                onChanged: (props) =>
                    setState(() => _consumerInputProperties = props),
              ),
              const SizedBox(height: 24),

              // Consumer Output Schema
              _buildSectionHeader('Consumer Output Schema'),
              const SizedBox(height: 8),
              Text(
                'Data returned by device after consumer provisioning',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              _buildSchemaEditor(
                properties: _consumerOutputProperties,
                onChanged: (props) =>
                    setState(() => _consumerOutputProperties = props),
              ),
              const SizedBox(height: 24),

              // Heartbeat Schema
              _buildSectionHeader('Heartbeat Schema'),
              const SizedBox(height: 8),
              Text(
                'Telemetry data sent in device heartbeats',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              _buildSchemaEditor(
                properties: _heartbeatProperties,
                onChanged: (props) =>
                    setState(() => _heartbeatProperties = props),
              ),
              if (_heartbeatProperties.isNotEmpty) ...[
                const SizedBox(height: 12),
                CborSizeIndicator(
                  estimate: _heartbeatEstimate,
                  label: 'This Capability\'s CBOR Size',
                  capabilityOnly: true,
                ),
              ],
              const SizedBox(height: 24),

              // Commands Section
              _buildSectionHeader('Commands'),
              const SizedBox(height: 8),
              Text(
                'Command definitions (tests, queries, actions)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              _buildCommandsEditor(),
              const SizedBox(height: 24),

              // Active status
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text(
                    'Inactive capabilities won\'t be available for device types'),
                value: _isActive,
                onChanged: (value) {
                  setState(() {
                    _isActive = value;
                  });
                },
              ),
              const SizedBox(height: 32),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: 'Cancel',
                      style: AppButtonStyle.secondary,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppButton(
                      text: isEditing ? 'Save Changes' : 'Create',
                      onPressed: _isLoading ? null : _handleSubmit,
                      isLoading: _isLoading,
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildSchemaEditor({
    required List<SchemaProperty> properties,
    required ValueChanged<List<SchemaProperty>> onChanged,
    int depth = 0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (properties.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            margin: EdgeInsets.only(left: depth * 24.0),
            decoration: BoxDecoration(
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  color: SaturdayColors.secondaryGrey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  depth == 0 ? 'No properties defined' : 'No nested properties',
                  style: TextStyle(
                    color: SaturdayColors.secondaryGrey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          )
        else
          ...properties.asMap().entries.map((entry) {
            final index = entry.key;
            final prop = entry.value;
            return _buildPropertyCard(
              prop: prop,
              depth: depth,
              onEdit: () => _editProperty(properties, index, onChanged),
              onDelete: () {
                final newList = List<SchemaProperty>.from(properties);
                newList.removeAt(index);
                onChanged(newList);
              },
              onChildrenChanged: prop.type == 'object'
                  ? (newChildren) {
                      final newList = List<SchemaProperty>.from(properties);
                      newList[index] = prop.copyWith(children: newChildren);
                      onChanged(newList);
                    }
                  : null,
            );
          }),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.only(left: depth * 24.0),
          child: OutlinedButton.icon(
            onPressed: () => _addProperty(properties, onChanged),
            icon: const Icon(Icons.add),
            label: Text(depth == 0 ? 'Add Property' : 'Add Nested Property'),
          ),
        ),
      ],
    );
  }

  Widget _buildPropertyCard({
    required SchemaProperty prop,
    required int depth,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
    ValueChanged<List<SchemaProperty>>? onChildrenChanged,
  }) {
    final isObject = prop.type == 'object';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: EdgeInsets.only(bottom: 8, left: depth * 24.0),
          color: depth > 0
              ? SaturdayColors.info.withValues(alpha: 0.05)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (depth > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: SaturdayColors.secondaryGrey,
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            prop.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (prop.isRequired)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SaturdayColors.error
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'required',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: SaturdayColors.error,
                                ),
                              ),
                            ),
                          if (isObject)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SaturdayColors.info
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${prop.children.length} nested',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: SaturdayColors.info,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        prop.type,
                        style: TextStyle(
                          fontSize: 12,
                          color: SaturdayColors.info,
                        ),
                      ),
                      if (_constraintsSummary(prop) != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _constraintsSummary(prop)!,
                          style: TextStyle(
                            fontSize: 12,
                            color: SaturdayColors.secondaryGrey,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      if (prop.description != null &&
                          prop.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          prop.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: SaturdayColors.secondaryGrey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: Icon(Icons.delete, size: 20, color: SaturdayColors.error),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ),
        // Show nested properties editor for object types
        if (isObject && onChildrenChanged != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildSchemaEditor(
              properties: prop.children,
              onChanged: onChildrenChanged,
              depth: depth + 1,
            ),
          ),
      ],
    );
  }

  void _addProperty(
      List<SchemaProperty> properties, ValueChanged<List<SchemaProperty>> onChanged) {
    _showPropertyDialog(
      title: 'Add Property',
      onSave: (prop) {
        final newList = List<SchemaProperty>.from(properties)..add(prop);
        onChanged(newList);
      },
    );
  }

  void _editProperty(List<SchemaProperty> properties, int index,
      ValueChanged<List<SchemaProperty>> onChanged) {
    _showPropertyDialog(
      title: 'Edit Property',
      property: properties[index],
      onSave: (prop) {
        final newList = List<SchemaProperty>.from(properties);
        newList[index] = prop;
        onChanged(newList);
      },
    );
  }

  void _showPropertyDialog({
    required String title,
    SchemaProperty? property,
    required ValueChanged<SchemaProperty> onSave,
  }) {
    final nameController = TextEditingController(text: property?.name ?? '');
    final descController =
        TextEditingController(text: property?.description ?? '');
    final enumController = TextEditingController(
      text: property?.enumValues?.join(', ') ?? '',
    );
    final minController = TextEditingController(
      text: property?.minimum?.toString() ?? '',
    );
    final maxController = TextEditingController(
      text: property?.maximum?.toString() ?? '',
    );
    String selectedType = property?.type ?? 'string';
    bool isRequired = property?.isRequired ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Property Name *',
                      hintText: 'e.g., device_id, temperature',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'string', child: Text('String')),
                      DropdownMenuItem(value: 'number', child: Text('Number')),
                      DropdownMenuItem(value: 'integer', child: Text('Integer')),
                      DropdownMenuItem(value: 'boolean', child: Text('Boolean')),
                      DropdownMenuItem(value: 'object', child: Text('Object')),
                      DropdownMenuItem(value: 'array', child: Text('Array')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedType = value ?? 'string';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Brief description of this property',
                    ),
                    maxLines: 2,
                  ),
                  if (_typeSupportsEnum(selectedType)) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: enumController,
                      decoration: const InputDecoration(
                        labelText: 'Allowed Values (enum)',
                        hintText: 'Comma-separated, e.g. red, green, blue',
                        helperText:
                            'Leave blank for no restriction. Integer/number values are coerced.',
                      ),
                    ),
                  ],
                  if (_typeSupportsRange(selectedType)) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minController,
                            decoration: const InputDecoration(
                              labelText: 'Minimum',
                              hintText: 'e.g., 0',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxController,
                            decoration: const InputDecoration(
                              labelText: 'Maximum',
                              hintText: 'e.g., 100',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Required'),
                    value: isRequired,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      setDialogState(() {
                        isRequired = value ?? false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Property name is required')),
                  );
                  return;
                }

                List<String>? enumValues;
                if (_typeSupportsEnum(selectedType)) {
                  final raw = enumController.text.trim();
                  if (raw.isNotEmpty) {
                    enumValues = raw
                        .split(',')
                        .map((v) => v.trim())
                        .where((v) => v.isNotEmpty)
                        .toList();
                    if (enumValues.isEmpty) enumValues = null;
                    if (selectedType != 'string' && enumValues != null) {
                      final bad = enumValues.firstWhere(
                        (v) => num.tryParse(v) == null,
                        orElse: () => '',
                      );
                      if (bad.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Enum value "$bad" is not a valid $selectedType',
                            ),
                          ),
                        );
                        return;
                      }
                    }
                  }
                }

                num? minimum;
                num? maximum;
                if (_typeSupportsRange(selectedType)) {
                  final minRaw = minController.text.trim();
                  final maxRaw = maxController.text.trim();
                  if (minRaw.isNotEmpty) {
                    minimum = num.tryParse(minRaw);
                    if (minimum == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Minimum must be a number'),
                        ),
                      );
                      return;
                    }
                  }
                  if (maxRaw.isNotEmpty) {
                    maximum = num.tryParse(maxRaw);
                    if (maximum == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Maximum must be a number'),
                        ),
                      );
                      return;
                    }
                  }
                  if (minimum != null &&
                      maximum != null &&
                      minimum > maximum) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Minimum must be ≤ maximum'),
                      ),
                    );
                    return;
                  }
                }

                onSave(SchemaProperty(
                  name: name,
                  type: selectedType,
                  description: descController.text.trim().isEmpty
                      ? null
                      : descController.text.trim(),
                  isRequired: isRequired,
                  enumValues: enumValues,
                  minimum: minimum,
                  maximum: maximum,
                  // Preserve children when editing an object
                  children: property?.children ?? const [],
                ));
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandsEditor() {
    return Column(
      children: [
        if (_commands.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.terminal,
                  color: SaturdayColors.secondaryGrey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'No commands defined',
                  style: TextStyle(
                    color: SaturdayColors.secondaryGrey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          )
        else
          ..._commands.asMap().entries.map((entry) {
            final index = entry.key;
            final command = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.terminal, color: SaturdayColors.info),
                title: Text(command.displayName),
                subtitle: Text(
                  command.description ?? command.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editCommand(index),
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: Icon(Icons.delete,
                          size: 20, color: SaturdayColors.error),
                      onPressed: () {
                        setState(() {
                          _commands.removeAt(index);
                        });
                      },
                      tooltip: 'Delete',
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addCommand,
          icon: const Icon(Icons.add),
          label: const Text('Add Command'),
        ),
      ],
    );
  }

  void _addCommand() {
    _showCommandDialog(
      title: 'Add Command',
      onSave: (command) {
        setState(() {
          _commands.add(command);
        });
      },
    );
  }

  void _editCommand(int index) {
    _showCommandDialog(
      title: 'Edit Command',
      command: _commands[index],
      onSave: (command) {
        setState(() {
          _commands[index] = command;
        });
      },
    );
  }

  void _showCommandDialog({
    required String title,
    CapabilityCommand? command,
    required ValueChanged<CapabilityCommand> onSave,
  }) {
    final nameController = TextEditingController(text: command?.name ?? '');
    final displayNameController =
        TextEditingController(text: command?.displayName ?? '');
    final descController =
        TextEditingController(text: command?.description ?? '');

    // Parse existing schemas into structured property lists.
    // A malformed scalar schema (no `properties`) parses to an empty list,
    // which is the correct recovery: the user starts fresh with the structured
    // editor, which always emits a well-formed object schema on save.
    List<SchemaProperty> paramsProperties =
        _parseSchemaProperties(command?.parametersSchema);
    List<SchemaProperty> resultProperties =
        _parseSchemaProperties(command?.resultSchema);

    final isMalformed = _isMalformedObjectSchema(command?.parametersSchema) ||
        _isMalformedObjectSchema(command?.resultSchema);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name (machine-readable) *',
                      hintText: 'e.g., connect, scan, get_dataset',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display Name *',
                      hintText: 'e.g., Connect to Wi-Fi',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'What this command does',
                    ),
                    maxLines: 2,
                  ),
                  if (isMalformed) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SaturdayColors.warning.withValues(alpha: 0.1),
                        border: Border.all(
                          color: SaturdayColors.warning.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber,
                              color: SaturdayColors.warning, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Existing schema was not an object with properties '
                              'and could not be loaded. Re-add the parameters '
                              'below; the device protocol requires params to be '
                              'an object.',
                              style: TextStyle(
                                fontSize: 12,
                                color: SaturdayColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildSectionHeader('Parameters Schema'),
                  const SizedBox(height: 4),
                  Text(
                    'Fields the technician fills in when running this command. '
                    'Sent as the `params` object.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondaryGrey,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _buildSchemaEditor(
                    properties: paramsProperties,
                    onChanged: (props) =>
                        setDialogState(() => paramsProperties = props),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Result Schema'),
                  const SizedBox(height: 4),
                  Text(
                    'Fields the device returns in the response `data` object.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondaryGrey,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _buildSchemaEditor(
                    properties: resultProperties,
                    onChanged: (props) =>
                        setDialogState(() => resultProperties = props),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final displayName = displayNameController.text.trim();

                if (name.isEmpty || displayName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Name and display name are required'),
                    ),
                  );
                  return;
                }

                onSave(CapabilityCommand(
                  name: name,
                  displayName: displayName,
                  description: descController.text.trim().isEmpty
                      ? null
                      : descController.text.trim(),
                  parametersSchema: _buildSchema(paramsProperties),
                  resultSchema: _buildSchema(resultProperties),
                ));
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// True if a schema is non-empty but not a usable object-with-properties
  /// schema. Used to warn the user when a legacy/hand-authored scalar schema
  /// can't be round-tripped through the structured editor.
  static bool _isMalformedObjectSchema(Map<String, dynamic>? schema) {
    if (schema == null || schema.isEmpty) return false;
    final properties = schema['properties'];
    return properties is! Map || properties.isEmpty;
  }

  CborSizeEstimate get _heartbeatEstimate {
    final sizeProps = _heartbeatProperties
        .map((p) => SchemaPropertySize(
              name: p.name,
              type: p.type,
              children: _toSizeChildren(p.children),
            ))
        .toList();
    return CborSizeEstimator.estimateHeartbeatSize(sizeProps);
  }

  List<SchemaPropertySize> _toSizeChildren(List<SchemaProperty> props) {
    return props
        .map((p) => SchemaPropertySize(
              name: p.name,
              type: p.type,
              children: _toSizeChildren(p.children),
            ))
        .toList();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Validate command name uniqueness before saving
      final repository = ref.read(capabilityRepositoryProvider);
      final conflicts = await repository.findCommandNameConflicts(
        commandNames: _commands.map((c) => c.name).toList(),
        excludeCapabilityId: widget.capability?.id,
      );
      if (conflicts.isNotEmpty) {
        if (mounted) {
          final conflictMessages = conflicts.entries
              .map((e) => "'${e.key}' is already used by ${e.value}")
              .join('\n');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Command name conflicts:\n$conflictMessages'),
              backgroundColor: SaturdayColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return; // Don't proceed with save
      }

      final management = ref.read(capabilityManagementProvider);

      if (widget.capability != null) {
        // Update existing capability
        final updatedCapability = widget.capability!.copyWith(
          name: _nameController.text.trim(),
          displayName: _displayNameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          factoryInputSchema: _buildSchema(_factoryInputProperties),
          factoryOutputSchema: _buildSchema(_factoryOutputProperties),
          consumerInputSchema: _buildSchema(_consumerInputProperties),
          consumerOutputSchema: _buildSchema(_consumerOutputProperties),
          heartbeatSchema: _buildSchema(_heartbeatProperties),
          commands: _commands,
          isActive: _isActive,
        );

        await management.updateCapability(updatedCapability);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Capability updated'),
              backgroundColor: SaturdayColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Create new capability
        final newCapability = Capability(
          id: '', // Will be generated by repository
          name: _nameController.text.trim(),
          displayName: _displayNameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          factoryInputSchema: _buildSchema(_factoryInputProperties),
          factoryOutputSchema: _buildSchema(_factoryOutputProperties),
          consumerInputSchema: _buildSchema(_consumerInputProperties),
          consumerOutputSchema: _buildSchema(_consumerOutputProperties),
          heartbeatSchema: _buildSchema(_heartbeatProperties),
          commands: _commands,
          isActive: _isActive,
          createdAt: DateTime.now(),
        );

        await management.createCapability(newCapability);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Capability created'),
              backgroundColor: SaturdayColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save capability: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

/// Helper class for schema property editing with nested support
class SchemaProperty {
  final String name;
  final String type;
  final String? description;
  final bool isRequired;
  final List<SchemaProperty> children; // For nested object properties
  final List<String>? enumValues;
  final num? minimum;
  final num? maximum;

  SchemaProperty({
    required this.name,
    required this.type,
    this.description,
    this.isRequired = false,
    List<SchemaProperty>? children,
    this.enumValues,
    this.minimum,
    this.maximum,
  }) : children = children ?? [];

  SchemaProperty copyWith({
    String? name,
    String? type,
    String? description,
    bool? isRequired,
    List<SchemaProperty>? children,
    List<String>? enumValues,
    num? minimum,
    num? maximum,
  }) {
    return SchemaProperty(
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      isRequired: isRequired ?? this.isRequired,
      children: children ?? this.children,
      enumValues: enumValues ?? this.enumValues,
      minimum: minimum ?? this.minimum,
      maximum: maximum ?? this.maximum,
    );
  }
}
