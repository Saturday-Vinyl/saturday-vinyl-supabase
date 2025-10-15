import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/services/gcode_sync_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Card for syncing gCode files from GitHub repository
class GCodeSyncCard extends StatefulWidget {
  const GCodeSyncCard({super.key});

  @override
  State<GCodeSyncCard> createState() => _GCodeSyncCardState();
}

class _GCodeSyncCardState extends State<GCodeSyncCard> {
  final GCodeSyncService _syncService = GCodeSyncService();

  bool _isSyncing = false;
  bool _isValidating = false;
  DateTime? _lastSyncTime;
  SyncResult? _lastSyncResult;
  bool? _connectionValid;

  @override
  void initState() {
    super.initState();
    _validateConnection();
  }

  Future<void> _validateConnection() async {
    setState(() => _isValidating = true);

    try {
      final isValid = await _syncService.validateConnection();
      setState(() {
        _connectionValid = isValid;
        _isValidating = false;
      });
    } catch (error) {
      AppLogger.error('Error validating GitHub connection', error, null);
      setState(() {
        _connectionValid = false;
        _isValidating = false;
      });
    }
  }

  Future<void> _syncRepository() async {
    setState(() {
      _isSyncing = true;
      _lastSyncResult = null;
    });

    try {
      final result = await _syncService.syncRepository();

      setState(() {
        _lastSyncTime = DateTime.now();
        _lastSyncResult = result;
        _isSyncing = false;
      });

      if (!mounted) return;

      // Show result message
      if (result.hasErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync completed with ${result.errors} errors. '
              'Added: ${result.filesAdded}, Updated: ${result.filesUpdated}, Deleted: ${result.filesDeleted}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      } else if (result.hasChanges) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sync successful! '
              'Added: ${result.filesAdded}, Updated: ${result.filesUpdated}, Deleted: ${result.filesDeleted}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync complete. No changes detected.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error syncing repository', error, stackTrace);

      setState(() => _isSyncing = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.sync,
                  size: 24,
                  color: SaturdayColors.primaryDark,
                ),
                const SizedBox(width: 12),
                const Text(
                  'gCode Repository Sync',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Sync gCode files from your GitHub repository',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Connection Status
            _buildConnectionStatus(),
            const SizedBox(height: 16),

            // Last Sync Info
            if (_lastSyncTime != null) ...[
              _buildLastSyncInfo(),
              const SizedBox(height: 16),
            ],

            // Sync Result
            if (_lastSyncResult != null) ...[
              _buildSyncResult(),
              const SizedBox(height: 16),
            ],

            // Sync Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _connectionValid == true && !_isSyncing
                    ? _syncRepository
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaturdayColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[600],
                ),
                icon: _isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.sync),
                label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
              ),
            ),

            // Help Text
            const SizedBox(height: 12),
            const Text(
              'This will scan your GitHub repository for .gcode files and update the local database. '
              'Files are organized by machine type (CNC/Laser) based on their folder structure.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF757575),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    if (_isValidating) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            'Validating connection...',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      );
    }

    if (_connectionValid == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Icon(
          _connectionValid! ? Icons.check_circle : Icons.error,
          color: _connectionValid! ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _connectionValid!
                ? 'GitHub connection valid'
                : 'GitHub connection failed. Check your credentials in .env file.',
            style: TextStyle(
              color: _connectionValid! ? Colors.green[700] : Colors.red[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (!_connectionValid!)
          TextButton(
            onPressed: _validateConnection,
            child: const Text('Retry'),
          ),
      ],
    );
  }

  Widget _buildLastSyncInfo() {
    final now = DateTime.now();
    final difference = now.difference(_lastSyncTime!);

    String timeAgo;
    if (difference.inMinutes < 1) {
      timeAgo = 'Just now';
    } else if (difference.inHours < 1) {
      timeAgo = '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else if (difference.inDays < 1) {
      timeAgo = '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else {
      timeAgo = '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Text(
            'Last synced: $timeAgo',
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue[900],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncResult() {
    final result = _lastSyncResult!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.hasErrors ? Colors.orange[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.hasErrors ? Colors.orange[200]! : Colors.green[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.hasErrors ? Icons.warning : Icons.check_circle,
                size: 16,
                color: result.hasErrors ? Colors.orange[700] : Colors.green[700],
              ),
              const SizedBox(width: 8),
              Text(
                result.hasErrors ? 'Completed with errors' : 'Sync successful',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: result.hasErrors ? Colors.orange[900] : Colors.green[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${result.filesAdded} added • '
            '${result.filesUpdated} updated • '
            '${result.filesDeleted} deleted'
            '${result.hasErrors ? ' • ${result.errors} errors' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: result.hasErrors ? Colors.orange[800] : Colors.green[800],
            ),
          ),
          if (result.hasErrors && result.errorMessages.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'Errors:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.orange[900],
              ),
            ),
            const SizedBox(height: 4),
            ...result.errorMessages.take(3).map((error) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                '• $error',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange[800],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            )),
            if (result.errorMessages.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  '... and ${result.errorMessages.length - 3} more',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.orange[700],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
