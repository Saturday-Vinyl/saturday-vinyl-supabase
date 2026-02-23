import 'dart:convert';
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
      );
    }).toList();
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
    String selectedType = property?.type ?? 'string';
    bool isRequired = property?.isRequired ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 400,
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
                onSave(SchemaProperty(
                  name: name,
                  type: selectedType,
                  description: descController.text.trim().isEmpty
                      ? null
                      : descController.text.trim(),
                  isRequired: isRequired,
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
    final descController = TextEditingController(text: command?.description ?? '');
    final paramsController = TextEditingController(
      text: command?.parametersSchema.isNotEmpty == true
          ? const JsonEncoder.withIndent('  ').convert(command!.parametersSchema)
          : '',
    );
    final resultController = TextEditingController(
      text: command?.resultSchema.isNotEmpty == true
          ? const JsonEncoder.withIndent('  ').convert(command!.resultSchema)
          : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 16),
                TextField(
                  controller: paramsController,
                  decoration: const InputDecoration(
                    labelText: 'Parameters Schema (JSON)',
                    hintText: '{"type": "object", "properties": {...}}',
                  ),
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resultController,
                  decoration: const InputDecoration(
                    labelText: 'Result Schema (JSON)',
                    hintText: '{"type": "object", "properties": {...}}',
                  ),
                  maxLines: 4,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
                      content: Text('Name and display name are required')),
                );
                return;
              }

              Map<String, dynamic> paramsSchema = {};
              Map<String, dynamic> resultSchema = {};

              try {
                if (paramsController.text.trim().isNotEmpty) {
                  paramsSchema = jsonDecode(paramsController.text.trim())
                      as Map<String, dynamic>;
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Invalid parameters JSON: $e')),
                );
                return;
              }

              try {
                if (resultController.text.trim().isNotEmpty) {
                  resultSchema = jsonDecode(resultController.text.trim())
                      as Map<String, dynamic>;
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Invalid result JSON: $e')),
                );
                return;
              }

              onSave(CapabilityCommand(
                name: name,
                displayName: displayName,
                description: descController.text.trim().isEmpty
                    ? null
                    : descController.text.trim(),
                parametersSchema: paramsSchema,
                resultSchema: resultSchema,
              ));
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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

  SchemaProperty({
    required this.name,
    required this.type,
    this.description,
    this.isRequired = false,
    List<SchemaProperty>? children,
  }) : children = children ?? [];

  SchemaProperty copyWith({
    String? name,
    String? type,
    String? description,
    bool? isRequired,
    List<SchemaProperty>? children,
  }) {
    return SchemaProperty(
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      isRequired: isRequired ?? this.isRequired,
      children: children ?? this.children,
    );
  }
}
