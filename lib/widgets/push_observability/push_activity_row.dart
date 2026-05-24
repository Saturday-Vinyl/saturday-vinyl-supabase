import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/push_observability.dart';
import 'package:saturday_app/providers/push_observability_provider.dart';
import 'package:saturday_app/repositories/push_observability_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// One row in the live activity feed or activity log table.
///
/// Tapping a row expands an inline details panel showing every field of the
/// delivery record with a per-field copy button — useful when debugging a
/// failure and you need to paste an id into Studio, Sentry, or a ticket.
class PushActivityRow extends ConsumerStatefulWidget {
  final PushDelivery delivery;
  final bool isLive;

  const PushActivityRow({
    super.key,
    required this.delivery,
    this.isLive = false,
  });

  @override
  ConsumerState<PushActivityRow> createState() => _PushActivityRowState();
}

class _PushActivityRowState extends ConsumerState<PushActivityRow> {
  bool _expanded = false;
  bool _retrying = false;
  PushRetryResult? _retryResult;

  Future<void> _onRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(pushObservabilityRepositoryProvider);

    try {
      final result = await repo.retryNotification(widget.delivery.id);
      if (!mounted) return;
      setState(() => _retryResult = result);

      messenger.showSnackBar(
        SnackBar(
          content: Text(result.success
              ? 'Retry sent'
              : 'Retry attempted but failed: ${result.error ?? "unknown"}'),
          backgroundColor: result.success
              ? SaturdayColors.success
              : SaturdayColors.error,
          duration: const Duration(seconds: 4),
        ),
      );

      ref.invalidate(pushDeliveriesProvider);
      ref.invalidate(pushStatsByTypeProvider);
      ref.invalidate(pushErrorPatternsProvider);
      ref.invalidate(pushHealthBucketsProvider);
    } on PushRetryException catch (e) {
      AppLogger.error('Retry failed: ${e.message}', e, StackTrace.current);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Retry failed: ${e.message}'),
          backgroundColor: SaturdayColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final isFailure = d.status == PushDeliveryStatus.failed;
    final canRetry =
        isFailure && retryableNotificationTypes.contains(d.notificationType);
    final bg = isFailure
        ? SaturdayColors.error.withValues(alpha: 0.05)
        : (widget.isLive
            ? SaturdayColors.info.withValues(alpha: 0.05)
            : Colors.white);

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.15),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusDot(status: d.status),
                const SizedBox(width: 10),
                SizedBox(
                  width: 88,
                  child: Text(
                    DateFormat('HH:mm:ss').format(d.createdAt),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: SaturdayColors.secondaryGrey,
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    d.notificationType,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    d.email ?? d.userId,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SaturdayColors.primaryDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (d.platform != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color:
                          SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      d.platform!,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: SaturdayColors.primaryDark,
                      ),
                    ),
                  ),
                if (widget.isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: SaturdayColors.info.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: SaturdayColors.info,
                      ),
                    ),
                  ),
                if (canRetry) _buildRetryButton(),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: SaturdayColors.secondaryGrey,
                  ),
                ),
              ],
            ),
            if (_expanded) _ExpandedDetails(delivery: d),
          ],
        ),
      ),
    );
  }

  Widget _buildRetryButton() {
    if (_retrying) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(SaturdayColors.primaryDark),
          ),
        ),
      );
    }
    if (_retryResult != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          _retryResult!.success ? 'Retried' : 'Retry failed',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _retryResult!.success
                ? SaturdayColors.success
                : SaturdayColors.error,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: TextButton.icon(
        onPressed: _onRetry,
        icon: const Icon(Icons.replay, size: 14),
        label: const Text('Retry'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: SaturdayColors.primaryDark,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Per-field expandable details panel with copy-to-clipboard on every value.
class _ExpandedDetails extends StatelessWidget {
  final PushDelivery delivery;

  const _ExpandedDetails({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final isoFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS");

    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 8, right: 8, bottom: 4),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CopyableField(label: 'Delivery ID', value: d.id),
            _CopyableField(
              label: 'Created at',
              value: isoFormat.format(d.createdAt),
            ),
            _CopyableField(label: 'Notification type', value: d.notificationType),
            _CopyableField(label: 'Status', value: d.status.displayName),
            if (d.email != null)
              _CopyableField(label: 'Email', value: d.email!),
            if (d.displayName != null)
              _CopyableField(label: 'Display name', value: d.displayName!),
            _CopyableField(label: 'User ID', value: d.userId),
            if (d.tokenId != null)
              _CopyableField(label: 'Token ID', value: d.tokenId!),
            if (d.deviceIdentifier != null)
              _CopyableField(
                  label: 'Device identifier', value: d.deviceIdentifier!),
            if (d.platform != null)
              _CopyableField(label: 'Platform', value: d.platform!),
            if (d.sourceId != null)
              _CopyableField(label: 'Source ID', value: d.sourceId!),
            if (d.sentAt != null)
              _CopyableField(
                  label: 'Sent at', value: isoFormat.format(d.sentAt!)),
            if (d.deliveredAt != null)
              _CopyableField(
                  label: 'Delivered at',
                  value: isoFormat.format(d.deliveredAt!)),
            if (d.sentByUserId != null)
              _CopyableField(
                  label: 'Sent by admin', value: d.sentByUserId!),
            if (d.errorMessage != null)
              _CopyableField(
                label: 'Error',
                value: d.errorMessage!,
                multiline: true,
                tone: _FieldTone.error,
              ),
          ],
        ),
      ),
    );
  }
}

enum _FieldTone { normal, error }

/// One label + value pair with an inline copy button.
///
/// Values use SelectableText so the user can also drag-select a substring;
/// the copy button is the one-tap path for the full value.
class _CopyableField extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;
  final _FieldTone tone;

  const _CopyableField({
    required this.label,
    required this.value,
    this.multiline = false,
    this.tone = _FieldTone.normal,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isError = tone == _FieldTone.error;
    final valueColor =
        isError ? SaturdayColors.error : SaturdayColors.primaryDark;
    final valueBg = isError
        ? SaturdayColors.error.withValues(alpha: 0.08)
        : SaturdayColors.light.withValues(alpha: 0.3);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: SaturdayColors.secondaryGrey,
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: valueBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                value,
                maxLines: multiline ? null : 1,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: valueColor,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 14),
            tooltip: 'Copy $label',
            color: SaturdayColors.secondaryGrey,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: () => _copy(context),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final PushDeliveryStatus status;
  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case PushDeliveryStatus.sent:
      case PushDeliveryStatus.delivered:
        color = SaturdayColors.success;
        break;
      case PushDeliveryStatus.failed:
        color = SaturdayColors.error;
        break;
      case PushDeliveryStatus.pending:
        color = SaturdayColors.warning;
        break;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
