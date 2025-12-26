import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/app_file.dart';
import 'package:saturday_app/providers/file_provider.dart';
import 'package:saturday_app/widgets/files/file_picker_dialog.dart';

/// Widget for selecting and managing files attached to a production step
class StepFileSelector extends ConsumerWidget {
  final String? stepId; // null for new steps not yet saved
  final List<String> selectedFileIds;
  final ValueChanged<List<String>> onFilesChanged;

  const StepFileSelector({
    super.key,
    this.stepId,
    required this.selectedFileIds,
    required this.onFilesChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attached Files',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            ElevatedButton.icon(
              onPressed: () => _showFilePicker(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Files'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.info,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Select files from your library to attach to this step. Drag to reorder.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
        const SizedBox(height: 16),

        // Show selected files
        if (selectedFileIds.isEmpty)
          _buildEmptyState(context)
        else
          _buildFilesList(context, ref),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SaturdayColors.light,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.folder_open,
            size: 48,
            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No files attached',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Click "Add Files" to attach files from your library',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.8),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: SaturdayColors.info),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: selectedFileIds.length,
        onReorder: (oldIndex, newIndex) {
          final ids = List<String>.from(selectedFileIds);
          if (oldIndex < newIndex) {
            newIndex -= 1;
          }
          final item = ids.removeAt(oldIndex);
          ids.insert(newIndex, item);
          onFilesChanged(ids);
        },
        itemBuilder: (context, index) {
          final fileId = selectedFileIds[index];
          final fileAsync = ref.watch(fileByIdProvider(fileId));

          return fileAsync.when(
            data: (file) {
              if (file == null) {
                return ListTile(
                  key: ValueKey(fileId),
                  leading: const Icon(Icons.error, color: SaturdayColors.error),
                  title: const Text('File not found'),
                  subtitle: Text('ID: $fileId'),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    color: SaturdayColors.error,
                    onPressed: () => _removeFile(fileId),
                  ),
                );
              }

              return _buildFileListItem(
                context,
                index,
                file,
                fileId,
              );
            },
            loading: () => ListTile(
              key: ValueKey(fileId),
              leading: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: const Text('Loading...'),
            ),
            error: (error, stack) => ListTile(
              key: ValueKey(fileId),
              leading: const Icon(Icons.error, color: SaturdayColors.error),
              title: const Text('Error loading file'),
              subtitle: Text(error.toString()),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: SaturdayColors.error,
                onPressed: () => _removeFile(fileId),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileListItem(
    BuildContext context,
    int index,
    AppFile file,
    String fileId,
  ) {
    return ListTile(
      key: ValueKey(fileId),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Order number
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: SaturdayColors.info,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Drag handle
          const Icon(Icons.drag_handle),
          const SizedBox(width: 8),
          // File icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _getFileIconColor(file).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _getFileIcon(file),
              color: _getFileIconColor(file),
              size: 18,
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              file.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // File type badge
          if (file.isGCodeFile)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: SaturdayColors.success.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'GCODE',
                style: TextStyle(
                  color: SaturdayColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: file.description != null
          ? Text(
              file.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline),
        color: SaturdayColors.error,
        onPressed: () => _removeFile(fileId),
        tooltip: 'Remove file',
      ),
    );
  }

  IconData _getFileIcon(AppFile file) {
    if (file.isGCodeFile) {
      return Icons.settings_input_component;
    }
    if (file.mimeType.startsWith('image/')) {
      return Icons.image;
    } else if (file.mimeType.contains('pdf')) {
      return Icons.picture_as_pdf;
    } else if (file.mimeType.contains('text')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  Color _getFileIconColor(AppFile file) {
    if (file.isGCodeFile) {
      return SaturdayColors.success;
    }
    if (file.mimeType.startsWith('image/')) {
      return Colors.blue;
    } else if (file.mimeType.contains('pdf')) {
      return Colors.red;
    } else if (file.mimeType.contains('text')) {
      return Colors.green;
    }
    return SaturdayColors.secondaryGrey;
  }

  void _removeFile(String fileId) {
    final ids = List<String>.from(selectedFileIds);
    ids.remove(fileId);
    onFilesChanged(ids);
  }

  Future<void> _showFilePicker(BuildContext context) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => FilePickerDialog(
        alreadySelectedFileIds: selectedFileIds,
        allowMultiple: true,
      ),
    );

    if (result != null) {
      onFilesChanged(result);
    }
  }
}
