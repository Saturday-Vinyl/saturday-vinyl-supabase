import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/push_observability.dart';
import 'package:saturday_app/providers/push_observability_provider.dart';
import 'package:saturday_app/repositories/push_observability_repository.dart';

/// Modal for sending an admin test push to a single token.
///
/// Routes through the `send-test-notification` edge function, which uses the
/// same `sendFcmPush` primitive as production — so a successful test means
/// production sends will also work.
class SendTestPushDialog extends ConsumerStatefulWidget {
  final PushDevice device;

  const SendTestPushDialog({super.key, required this.device});

  static Future<void> show(BuildContext context, PushDevice device) {
    return showDialog<void>(
      context: context,
      builder: (_) => SendTestPushDialog(device: device),
    );
  }

  @override
  ConsumerState<SendTestPushDialog> createState() =>
      _SendTestPushDialogState();
}

class _SendTestPushDialogState extends ConsumerState<SendTestPushDialog> {
  static const int _maxTitle = 200;
  static const int _maxBody = 500;

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  final _formKey = GlobalKey<FormState>();

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: 'Saturday admin test');
    _bodyController = TextEditingController(
      text: 'If you can see this, push delivery is working.',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _onSend() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(pushObservabilityRepositoryProvider);

    try {
      final result = await repo.sendTestNotification(
        tokenId: widget.device.tokenId,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
      );

      // Refresh dependent reads so the new admin_test row shows up.
      ref.invalidate(pushDeliveriesProvider);
      ref.invalidate(pushStatsByTypeProvider);
      ref.invalidate(pushHealthBucketsProvider);
      ref.invalidate(pushDevicesProvider);

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.success
              ? 'Test push sent to ${widget.device.displayName ?? widget.device.email ?? "device"}'
              : 'Push failed: ${result.error ?? "unknown error"}'),
          backgroundColor: result.success
              ? SaturdayColors.success
              : SaturdayColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } on PushRetryException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Test send failed: ${e.message}'),
          backgroundColor: SaturdayColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final recipient = d.displayName ?? d.email ?? d.userId;

    return AlertDialog(
      title: const Text('Send test push'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TargetRow(recipient: recipient, platform: d.platform),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                enabled: !_sending,
                maxLength: _maxTitle,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Shown in the notification banner',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyController,
                enabled: !_sending,
                maxLength: _maxBody,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  hintText: 'Notification body text',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Body is required' : null,
              ),
              const SizedBox(height: 8),
              const Text(
                'Logged as notification_type=admin_test with sent_by_user_id set to you.',
                style: TextStyle(
                  fontSize: 11,
                  color: SaturdayColors.secondaryGrey,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _sending ? null : _onSend,
          icon: _sending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.send, size: 16),
          label: Text(_sending ? 'Sending…' : 'Send'),
        ),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  final String recipient;
  final String platform;

  const _TargetRow({required this.recipient, required this.platform});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SaturdayColors.light.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_iphone,
              size: 18, color: SaturdayColors.secondaryGrey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipient,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Platform: $platform',
                  style: const TextStyle(
                    fontSize: 11,
                    color: SaturdayColors.secondaryGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
