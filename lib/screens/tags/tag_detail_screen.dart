import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/providers/rfid_tag_provider.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/widgets/tags/tag_status_badge.dart';

/// Detail screen/panel for viewing a single RFID tag
class TagDetailScreen extends ConsumerStatefulWidget {
  final String tagId;

  const TagDetailScreen({
    super.key,
    required this.tagId,
  });

  /// Show as a modal bottom sheet
  static Future<void> show(BuildContext context, String tagId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: TagDetailScreen(tagId: tagId),
        ),
      ),
    );
  }

  @override
  ConsumerState<TagDetailScreen> createState() => _TagDetailScreenState();
}

class _TagDetailScreenState extends ConsumerState<TagDetailScreen> {
  bool _isRetiring = false;
  bool _isSavingQR = false;
  bool _isGeneratingQR = false;
  Uint8List? _qrCodeData;
  String? _lastGeneratedEpc;
  final _qrService = QRService();

  @override
  Widget build(BuildContext context) {
    final tagAsync = ref.watch(rfidTagByIdProvider(widget.tagId));

    return tagAsync.when(
      data: (tag) {
        if (tag == null) {
          return _buildErrorState('Tag not found');
        }
        // Auto-generate QR code when tag loads (only once per EPC)
        if (_qrCodeData == null || _lastGeneratedEpc != tag.epcIdentifier) {
          _generateQRCode(tag);
        }
        return _buildContent(context, tag);
      },
      loading: () => _buildLoadingState(),
      error: (error, _) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: SaturdayColors.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: SaturdayColors.error),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, RfidTag tag) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: SaturdayColors.secondaryGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header with QR Code
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // QR Code
              GestureDetector(
                onTap: () => _saveQRCode(tag),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: _qrCodeData != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.memory(
                            _qrCodeData!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                        )
                      : Center(
                          child: _isGeneratingQR
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(
                                  Icons.qr_code,
                                  size: 40,
                                  color: SaturdayColors.secondaryGrey,
                                ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Tag Details',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    TagStatusBadge(status: tag.status),
                    const SizedBox(height: 8),
                    // Save QR button
                    if (_qrCodeData != null)
                      TextButton.icon(
                        onPressed: _isSavingQR ? null : () => _saveQRCode(tag),
                        icon: _isSavingQR
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_alt, size: 16),
                        label: Text(
                          _isSavingQR ? 'Saving...' : 'Save QR Code',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // EPC Identifier
          _buildSection(
            context,
            title: 'EPC Identifier',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tag.formattedEpc,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copyToClipboard(tag.epcIdentifier),
                  tooltip: 'Copy EPC',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Factory TID
          if (tag.tid != null && tag.tid!.isNotEmpty)
            _buildSection(
              context,
              title: 'Factory TID',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tag.tid!.toUpperCase(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(tag.tid!),
                    tooltip: 'Copy TID',
                  ),
                ],
              ),
            ),

          if (tag.tid != null && tag.tid!.isNotEmpty) const SizedBox(height: 24),

          // Timeline
          _buildSection(
            context,
            title: 'Timeline',
            child: Column(
              children: [
                _buildTimelineItem(
                  context,
                  icon: Icons.auto_awesome,
                  title: 'Created',
                  subtitle: _formatDateTime(tag.createdAt),
                  isCompleted: true,
                ),
                if (tag.writtenAt != null)
                  _buildTimelineItem(
                    context,
                    icon: Icons.edit_note,
                    title: 'Written',
                    subtitle: _formatDateTime(tag.writtenAt!),
                    isCompleted: true,
                  ),
                if (tag.lockedAt != null)
                  _buildTimelineItem(
                    context,
                    icon: Icons.lock,
                    title: 'Locked',
                    subtitle: _formatDateTime(tag.lockedAt!),
                    isCompleted: true,
                    isLast: true,
                  ),
                if (tag.status == RfidTagStatus.retired)
                  _buildTimelineItem(
                    context,
                    icon: Icons.cancel_outlined,
                    title: 'Retired',
                    subtitle: _formatDateTime(tag.updatedAt),
                    isCompleted: true,
                    isLast: true,
                    color: const Color(0xFF5C5C5C),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Actions
          if (tag.status != RfidTagStatus.retired) ...[
            const Divider(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isRetiring ? null : () => _confirmRetire(tag),
                icon: _isRetiring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined, size: 18),
                label: Text(_isRetiring ? 'Retiring...' : 'Mark as Retired'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SaturdayColors.error,
                  side: BorderSide(color: SaturdayColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: SaturdayColors.secondaryGrey,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildTimelineItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isCompleted,
    bool isLast = false,
    Color? color,
  }) {
    final itemColor = color ?? (isCompleted ? SaturdayColors.success : SaturdayColors.secondaryGrey);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: itemColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: itemColor, width: 2),
              ),
              child: Icon(icon, size: 16, color: itemColor),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: itemColor.withValues(alpha: 0.3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('MMM d, y \'at\' h:mm a').format(dateTime);
  }

  Future<void> _generateQRCode(RfidTag tag) async {
    // Prevent duplicate generation
    if (_isGeneratingQR || _lastGeneratedEpc == tag.epcIdentifier) return;

    setState(() {
      _isGeneratingQR = true;
      _lastGeneratedEpc = tag.epcIdentifier;
    });

    try {
      final qrData = await _qrService.generateTagQRCode(
        tag.epcIdentifier,
        size: 512,
      );

      if (mounted) {
        setState(() {
          _qrCodeData = qrData;
          _isGeneratingQR = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGeneratingQR = false;
          _lastGeneratedEpc = null; // Allow retry on error
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate QR code: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveQRCode(RfidTag tag) async {
    if (_qrCodeData == null) return;

    setState(() => _isSavingQR = true);

    try {
      final filename = QRService.formatTagFilename(tag.epcIdentifier);
      final savedPath = await _qrService.saveQRCodeToFile(_qrCodeData!, filename);

      if (mounted) {
        setState(() => _isSavingQR = false);
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('QR code saved to $savedPath'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingQR = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save QR code: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        backgroundColor: SaturdayColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmRetire(RfidTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retire Tag?'),
        content: Text(
          'Are you sure you want to retire this tag?\n\n'
          'EPC: ${tag.formattedEpc}\n\n'
          'This action cannot be undone.',
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
            child: const Text('Retire'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRetiring = true);

    try {
      final management = ref.read(rfidTagManagementProvider);
      await management.retireTag(tag.id);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Tag retired successfully'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to retire tag: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRetiring = false);
      }
    }
  }
}
