import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/app_file.dart';

/// List item widget for displaying a file in the file library
class FileListItem extends StatelessWidget {
  final AppFile file;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  const FileListItem({
    super.key,
    required this.file,
    required this.onEdit,
    required this.onDelete,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // File icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getFileIconColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getFileIcon(),
                  color: _getFileIconColor(),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),

              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // File name
                    Text(
                      file.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Description or placeholder
                    Text(
                      file.description ?? 'No description',
                      style: TextStyle(
                        color: file.description != null
                            ? SaturdayColors.secondaryGrey
                            : SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Metadata row
                    Row(
                      children: [
                        // File type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getFileIconColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            file.fileExtension.isEmpty
                                ? 'FILE'
                                : file.fileExtension.substring(1).toUpperCase(),
                            style: TextStyle(
                              color: _getFileIconColor(),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // File size
                        Icon(
                          Icons.data_usage,
                          size: 14,
                          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          file.fileSizeFormatted,
                          style: TextStyle(
                            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Upload info
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            file.uploadedByName,
                            style: TextStyle(
                              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: onDownload,
                    tooltip: 'Download',
                    iconSize: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: onEdit,
                    tooltip: 'Edit',
                    iconSize: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    tooltip: 'Delete',
                    color: SaturdayColors.error,
                    iconSize: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon() {
    if (file.isGCodeFile) {
      return Icons.settings_input_component; // CNC/gcode icon
    }

    // Check MIME type
    if (file.mimeType.startsWith('image/')) {
      return Icons.image;
    } else if (file.mimeType.startsWith('video/')) {
      return Icons.video_file;
    } else if (file.mimeType.startsWith('audio/')) {
      return Icons.audio_file;
    } else if (file.mimeType.contains('pdf')) {
      return Icons.picture_as_pdf;
    } else if (file.mimeType.contains('text') || file.mimeType.contains('json')) {
      return Icons.description;
    } else if (file.mimeType.contains('zip') || file.mimeType.contains('compressed')) {
      return Icons.folder_zip;
    }

    return Icons.insert_drive_file;
  }

  Color _getFileIconColor() {
    if (file.isGCodeFile) {
      return SaturdayColors.success; // CNC/gcode files
    }

    if (file.mimeType.startsWith('image/')) {
      return Colors.blue;
    } else if (file.mimeType.startsWith('video/')) {
      return Colors.purple;
    } else if (file.mimeType.startsWith('audio/')) {
      return Colors.orange;
    } else if (file.mimeType.contains('pdf')) {
      return Colors.red;
    } else if (file.mimeType.contains('text') || file.mimeType.contains('json')) {
      return Colors.green;
    } else if (file.mimeType.contains('zip') || file.mimeType.contains('compressed')) {
      return Colors.amber;
    }

    return SaturdayColors.secondaryGrey;
  }
}
