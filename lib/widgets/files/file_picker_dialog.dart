import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/app_file.dart';
import 'package:saturday_app/providers/file_provider.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

/// Dialog for picking files from the library to attach to production steps
class FilePickerDialog extends ConsumerStatefulWidget {
  final List<String> alreadySelectedFileIds;
  final bool allowMultiple;

  const FilePickerDialog({
    super.key,
    this.alreadySelectedFileIds = const [],
    this.allowMultiple = true,
  });

  @override
  ConsumerState<FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends ConsumerState<FilePickerDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedFileIds = {};

  @override
  void initState() {
    super.initState();
    _selectedFileIds.addAll(widget.alreadySelectedFileIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _toggleFileSelection(String fileId) {
    setState(() {
      if (_selectedFileIds.contains(fileId)) {
        _selectedFileIds.remove(fileId);
      } else {
        if (!widget.allowMultiple) {
          _selectedFileIds.clear();
        }
        _selectedFileIds.add(fileId);
      }
    });
  }

  void _handleDone() {
    Navigator.of(context).pop(_selectedFileIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    final filesAsync = _searchQuery.isEmpty
        ? ref.watch(allFilesProvider)
        : ref.watch(fileSearchProvider(_searchQuery));

    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.folder_open, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Files',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        widget.allowMultiple
                            ? 'Choose one or more files from your library'
                            : 'Choose a file from your library',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Search bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search files...',
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
                ),
                filled: true,
                fillColor: SaturdayColors.light,
              ),
              onChanged: _handleSearch,
            ),

            const SizedBox(height: 16),

            // Selected count
            if (_selectedFileIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SaturdayColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SaturdayColors.info),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: SaturdayColors.info,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedFileIds.length} ${_selectedFileIds.length == 1 ? 'file' : 'files'} selected',
                      style: TextStyle(
                        color: SaturdayColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Files list
            Expanded(
              child: filesAsync.when(
                data: (files) {
                  if (files.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isEmpty
                                ? Icons.folder_open
                                : Icons.search_off,
                            size: 64,
                            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No files in your library'
                                : 'No files found',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: SaturdayColors.secondaryGrey,
                                ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final isSelected = _selectedFileIds.contains(file.id);
                      final isAlreadyAttached = widget.alreadySelectedFileIds.contains(file.id);

                      return FilePickerItem(
                        file: file,
                        isSelected: isSelected,
                        isAlreadyAttached: isAlreadyAttached,
                        onTap: () => _toggleFileSelection(file.id),
                      );
                    },
                  );
                },
                loading: () => const LoadingIndicator(
                  message: 'Loading files...',
                ),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: SaturdayColors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load files',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedFileIds.isEmpty ? null : _handleDone,
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual file item in the picker
class FilePickerItem extends StatelessWidget {
  final AppFile file;
  final bool isSelected;
  final bool isAlreadyAttached;
  final VoidCallback onTap;

  const FilePickerItem({
    super.key,
    required this.file,
    required this.isSelected,
    required this.isAlreadyAttached,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected
            ? SaturdayColors.info.withValues(alpha: 0.1)
            : null,
        child: Row(
          children: [
            // Checkbox
            Checkbox(
              value: isSelected,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 12),

            // File icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getFileIconColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                _getFileIcon(),
                color: _getFileIconColor(),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          file.fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isAlreadyAttached)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: SaturdayColors.info.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ATTACHED',
                            style: TextStyle(
                              color: SaturdayColors.info,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file.description ?? 'No description',
                    style: TextStyle(
                      color: file.description != null
                          ? SaturdayColors.secondaryGrey
                          : SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        file.fileExtension.isEmpty
                            ? 'FILE'
                            : file.fileExtension.substring(1).toUpperCase(),
                        style: TextStyle(
                          color: _getFileIconColor(),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        file.fileSizeFormatted,
                        style: TextStyle(
                          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon() {
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

  Color _getFileIconColor() {
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
}
