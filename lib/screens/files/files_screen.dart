import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/app_file.dart';
import 'package:saturday_app/providers/file_provider.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/files/file_list_item.dart';
import 'package:saturday_app/widgets/files/file_upload_dialog.dart';

/// Screen displaying the file library with upload, edit, and delete functionality
class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});

  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (context) => const FileUploadDialog(),
    );
  }

  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use search provider if searching, otherwise all files
    final filesAsync = _searchQuery.isEmpty
        ? ref.watch(allFilesProvider)
        : ref.watch(fileSearchProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          // Upload button
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: _showUploadDialog,
              icon: const Icon(Icons.upload_file, size: 20),
              label: const Text('Upload File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.success,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: SaturdayColors.light,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search files by name or description...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _handleSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _handleSearch,
            ),
          ),

          // Files list
          Expanded(
            child: filesAsync.when(
              data: (files) {
                if (files.isEmpty) {
                  if (_searchQuery.isNotEmpty) {
                    return EmptyState(
                      icon: Icons.search_off,
                      message: 'No files found matching "$_searchQuery"',
                      actionLabel: 'Clear Search',
                      onAction: () {
                        _searchController.clear();
                        _handleSearch('');
                      },
                    );
                  }

                  return EmptyState(
                    icon: Icons.folder_open,
                    message: 'No files in your library.\nUpload files to get started.',
                    actionLabel: 'Upload File',
                    onAction: _showUploadDialog,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(allFilesProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: files.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return FileListItem(
                        file: file,
                        onEdit: () => _handleEditFile(file),
                        onDelete: () => _handleDeleteFile(file),
                        onDownload: () => _handleDownloadFile(file),
                      );
                    },
                  ),
                );
              },
              loading: () => const LoadingIndicator(
                message: 'Loading files...',
              ),
              error: (error, stack) => ErrorState(
                message: 'Failed to load files',
                details: error.toString(),
                onRetry: () {
                  ref.invalidate(allFilesProvider);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleEditFile(AppFile file) {
    showDialog(
      context: context,
      builder: (context) => FileEditDialog(file: file),
    );
  }

  Future<void> _handleDeleteFile(AppFile file) async {
    // Check if file is used in any steps
    final fileManagement = ref.read(fileManagementProvider);
    final stepsUsingFile = await fileManagement.getStepsUsingFile(file.id);

    if (!mounted) return;

    // Show warning if file is in use
    if (stepsUsingFile.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('File In Use'),
          content: Text(
            'This file is used in ${stepsUsingFile.length} production step(s). '
            'Deleting it will remove it from those steps.\n\n'
            'Are you sure you want to delete "${file.fileName}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    } else {
      // Show simple confirmation if not in use
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete File'),
          content: Text('Are you sure you want to delete "${file.fileName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    // Delete the file
    try {
      await fileManagement.deleteFile(file);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.fileName} deleted successfully'),
          backgroundColor: SaturdayColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete file: $error'),
          backgroundColor: SaturdayColors.error,
        ),
      );
    }
  }

  Future<void> _handleDownloadFile(AppFile file) async {
    try {
      final fileManagement = ref.read(fileManagementProvider);
      await fileManagement.downloadFile(file);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.fileName} downloaded successfully'),
          backgroundColor: SaturdayColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download file: $error'),
          backgroundColor: SaturdayColors.error,
        ),
      );
    }
  }
}

/// File edit dialog widget
class FileEditDialog extends ConsumerStatefulWidget {
  final AppFile file;

  const FileEditDialog({
    super.key,
    required this.file,
  });

  @override
  ConsumerState<FileEditDialog> createState() => _FileEditDialogState();
}

class _FileEditDialogState extends ConsumerState<FileEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.file.fileName);
    _descriptionController = TextEditingController(text: widget.file.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final fileName = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    // Validation
    if (fileName.isEmpty) {
      setState(() {
        _errorMessage = 'File name is required';
      });
      return;
    }

    // Check if name changed and is available
    if (fileName != widget.file.fileName) {
      final fileManagement = ref.read(fileManagementProvider);
      final isAvailable = await fileManagement.isFileNameAvailable(
        fileName,
        excludeFileId: widget.file.id,
      );

      if (!isAvailable) {
        setState(() {
          _errorMessage = 'A file with this name already exists';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final updatedFile = widget.file.copyWith(
        fileName: fileName,
        description: description.isEmpty ? null : description,
        updatedAt: DateTime.now(),
      );

      final fileManagement = ref.read(fileManagementProvider);
      await fileManagement.updateFile(updatedFile);

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File updated successfully'),
          backgroundColor: SaturdayColors.success,
        ),
      );
    } catch (error) {
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit File'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'File Name',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              enabled: !_isLoading,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SaturdayColors.error),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: SaturdayColors.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleSave,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
