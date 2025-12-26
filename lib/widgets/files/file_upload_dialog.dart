import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/file_provider.dart';
import 'package:saturday_app/services/file_storage_service.dart';

/// Dialog for uploading a new file to the library
class FileUploadDialog extends ConsumerStatefulWidget {
  const FileUploadDialog({super.key});

  @override
  ConsumerState<FileUploadDialog> createState() => _FileUploadDialogState();
}

class _FileUploadDialogState extends ConsumerState<FileUploadDialog> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  PlatformFile? _selectedFile;
  Uint8List? _fileBytes;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // Load file bytes
      );

      if (result == null || result.files.isEmpty) {
        return; // User cancelled
      }

      final file = result.files.first;

      // Validate file size (50MB)
      if (file.size > FileStorageService.maxFileSizeBytes) {
        setState(() {
          _errorMessage =
              'File size (${(file.size / 1024 / 1024).toStringAsFixed(1)}MB) '
              'exceeds maximum allowed size (${FileStorageService.maxFileSizeMB}MB)';
        });
        return;
      }

      // Check if bytes are available
      if (file.bytes == null) {
        setState(() {
          _errorMessage = 'Failed to read file contents';
        });
        return;
      }

      setState(() {
        _selectedFile = file;
        _fileBytes = file.bytes;
        _errorMessage = null;
        // Auto-fill name if empty
        if (_nameController.text.isEmpty) {
          _nameController.text = file.name;
        }
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Failed to pick file: $error';
      });
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFile == null || _fileBytes == null) {
      setState(() {
        _errorMessage = 'Please select a file';
      });
      return;
    }

    final fileName = _nameController.text.trim();
    final description = _descriptionController.text.trim();

    // Validation
    if (fileName.isEmpty) {
      setState(() {
        _errorMessage = 'File name is required';
      });
      return;
    }

    // Check if name is available
    final fileManagement = ref.read(fileManagementProvider);
    final isAvailable = await fileManagement.isFileNameAvailable(fileName);

    if (!isAvailable) {
      setState(() {
        _errorMessage = 'A file with this name already exists';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Determine MIME type
      final mimeType = _selectedFile!.extension != null
          ? _getMimeType(_selectedFile!.extension!)
          : 'application/octet-stream';

      await fileManagement.uploadFile(
        fileBytes: _fileBytes!,
        fileName: fileName,
        description: description,
        mimeType: mimeType,
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File uploaded successfully'),
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

  String _getMimeType(String extension) {
    // Remove leading dot if present
    final ext = extension.toLowerCase().replaceAll('.', '');

    // Common MIME types
    switch (ext) {
      // Documents
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';

      // Images
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'svg':
        return 'image/svg+xml';
      case 'webp':
        return 'image/webp';

      // CNC/gcode files
      case 'gcode':
      case 'nc':
        return 'text/plain';

      // Archives
      case 'zip':
        return 'application/zip';
      case 'tar':
        return 'application/x-tar';
      case 'gz':
        return 'application/gzip';

      // Default
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload File'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File picker button
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(
                _selectedFile == null
                    ? 'Choose File'
                    : _selectedFile!.name,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),

            // Show file info if selected
            if (_selectedFile != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.light,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: SaturdayColors.success,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedFile!.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Size: ${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                      style: TextStyle(
                        fontSize: 12,
                        color: SaturdayColors.secondaryGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // File name field
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'File Name',
                hintText: 'Enter a unique file name',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),

            const SizedBox(height: 16),

            // Description field
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Add a description for this file',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              enabled: !_isLoading,
            ),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SaturdayColors.error),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: SaturdayColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: SaturdayColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Upload progress
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Uploading file...',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
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
          onPressed: _isLoading || _selectedFile == null ? null : _handleUpload,
          child: const Text('Upload'),
        ),
      ],
    );
  }
}
