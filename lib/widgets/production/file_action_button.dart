import 'dart:io';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/file_launcher_service.dart';
import '../../utils/app_logger.dart';

/// Reusable button for file actions (open/download)
///
/// On desktop: Opens file in configured or default application
/// On mobile: Downloads file to device
class FileActionButton extends StatefulWidget {
  /// URL of the file to open/download
  final String fileUrl;

  /// Name of the file including extension
  final String fileName;

  /// File extension (e.g., ".gcode", ".svg")
  final String fileType;

  /// Optional callback when file action completes successfully
  final VoidCallback? onSuccess;

  /// Optional callback when file action fails
  final Function(String error)? onError;

  const FileActionButton({
    super.key,
    required this.fileUrl,
    required this.fileName,
    required this.fileType,
    this.onSuccess,
    this.onError,
  });

  @override
  State<FileActionButton> createState() => _FileActionButtonState();
}

class _FileActionButtonState extends State<FileActionButton> {
  final FileLauncherService _fileLauncher = FileLauncherService();
  bool _isLoading = false;

  Future<void> _handleFileAction() async {
    setState(() => _isLoading = true);

    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        // Desktop: Open file in application
        await _openFile();
      } else {
        // Mobile: Download file
        await _downloadFile();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openFile() async {
    try {
      AppLogger.info('Opening file: ${widget.fileName}');

      final result = await _fileLauncher.openProductionFile(
        fileUrl: widget.fileUrl,
        fileName: widget.fileName,
        fileType: widget.fileType,
      );

      if (!mounted) return;

      if (result.success) {
        // Get the app name that will open the file
        final appName =
            await _fileLauncher.getAppNameForFileType(widget.fileType);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opened ${widget.fileName} in $appName'),
            backgroundColor: SaturdayColors.success,
          ),
        );

        widget.onSuccess?.call();
      } else {
        // Handle failure
        final message = result.errorMessage ?? 'Failed to open file';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (result.suggestion != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    result.suggestion!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
            backgroundColor: SaturdayColors.error,
            duration: const Duration(seconds: 6),
          ),
        );

        widget.onError?.call(message);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error opening file', e, stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening file: $e'),
          backgroundColor: SaturdayColors.error,
        ),
      );

      widget.onError?.call(e.toString());
    }
  }

  Future<void> _downloadFile() async {
    // TODO: Implement mobile download functionality
    // For now, just show a message
    AppLogger.info('Mobile download not yet implemented');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mobile download coming soon'),
        backgroundColor: SaturdayColors.info,
      ),
    );
  }

  String _getButtonText() {
    if (_isLoading) {
      return Platform.isMacOS || Platform.isWindows || Platform.isLinux
          ? 'Opening...'
          : 'Downloading...';
    }

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return 'Open File';
    } else {
      return 'Download File';
    }
  }

  IconData _getButtonIcon() {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return Icons.open_in_new;
    } else {
      return Icons.download;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _handleFileAction,
      icon: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(_getButtonIcon()),
      label: Text(_getButtonText()),
      style: ElevatedButton.styleFrom(
        backgroundColor: SaturdayColors.success,
        foregroundColor: Colors.white,
      ),
    );
  }
}
