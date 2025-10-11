import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';

/// A reusable file upload widget with drag-and-drop support
/// Displays selected file info and allows file selection
class FileUploadWidget extends StatelessWidget {
  final String? selectedFileName;
  final int? selectedFileSize;
  final VoidCallback onPickFile;
  final VoidCallback? onClearFile;
  final String label;
  final String? helpText;
  final List<String>? allowedExtensions;
  final int? maxFileSizeMB;

  const FileUploadWidget({
    super.key,
    this.selectedFileName,
    this.selectedFileSize,
    required this.onPickFile,
    this.onClearFile,
    this.label = 'Select File',
    this.helpText,
    this.allowedExtensions,
    this.maxFileSizeMB,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = selectedFileName != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // File info card (shown when file is selected)
        if (hasFile) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SaturdayColors.light,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SaturdayColors.primaryDark.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  _getFileIcon(),
                  color: SaturdayColors.primaryDark,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedFileName!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (selectedFileSize != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatFileSize(selectedFileSize!),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SaturdayColors.secondaryGrey,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onClearFile != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClearFile,
                    tooltip: 'Remove file',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Upload button
        OutlinedButton.icon(
          onPressed: onPickFile,
          icon: Icon(hasFile ? Icons.change_circle : Icons.upload_file),
          label: Text(hasFile ? 'Change File' : label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            side: BorderSide(
              color: SaturdayColors.primaryDark.withOpacity(0.5),
              width: 1.5,
            ),
          ),
        ),

        // Help text
        if (helpText != null || allowedExtensions != null || maxFileSizeMB != null) ...[
          const SizedBox(height: 8),
          Text(
            _buildHelpText(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
        ],
      ],
    );
  }

  String _buildHelpText() {
    final parts = <String>[];

    if (helpText != null) {
      parts.add(helpText!);
    }

    if (allowedExtensions != null && allowedExtensions!.isNotEmpty) {
      parts.add('Allowed: ${allowedExtensions!.join(', ')}');
    }

    if (maxFileSizeMB != null) {
      parts.add('Max size: ${maxFileSizeMB}MB');
    }

    return parts.join(' • ');
  }

  IconData _getFileIcon() {
    if (selectedFileName == null) return Icons.insert_drive_file;

    final extension = selectedFileName!.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return Icons.video_file;
      case 'doc':
      case 'docx':
      case 'txt':
        return Icons.description;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'bin':
      case 'hex':
        return Icons.memory;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}

/// Helper class for file picking with validation
class FileUploadHelper {
  /// Pick a file with optional type and size validation
  static Future<FileUploadResult?> pickFile({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    int? maxFileSizeMB,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;

      // Validate file size
      if (maxFileSizeMB != null && file.size > maxFileSizeMB * 1024 * 1024) {
        return FileUploadResult(
          error: 'File size exceeds maximum allowed size of ${maxFileSizeMB}MB',
        );
      }

      // Check if we have a valid path
      if (file.path == null) {
        return FileUploadResult(
          error: 'Could not access file path',
        );
      }

      return FileUploadResult(
        file: File(file.path!),
        fileName: file.name,
        fileSize: file.size,
      );
    } catch (error) {
      return FileUploadResult(
        error: 'Failed to pick file: $error',
      );
    }
  }
}

/// Result of file upload operation
class FileUploadResult {
  final File? file;
  final String? fileName;
  final int? fileSize;
  final String? error;

  FileUploadResult({
    this.file,
    this.fileName,
    this.fileSize,
    this.error,
  });

  bool get hasError => error != null;
  bool get hasFile => file != null;
}
