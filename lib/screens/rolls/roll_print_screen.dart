import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/providers/niimbot_provider.dart';
import 'package:saturday_app/providers/rfid_tag_roll_provider.dart';
import 'package:saturday_app/providers/roll_print_provider.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

/// Screen for batch printing QR labels for a roll
///
/// This screen handles printing all labels in sequence with
/// start, pause, resume, and stop controls.
class RollPrintScreen extends ConsumerStatefulWidget {
  final String rollId;
  final int? startFromPosition;

  const RollPrintScreen({
    super.key,
    required this.rollId,
    this.startFromPosition,
  });

  @override
  ConsumerState<RollPrintScreen> createState() => _RollPrintScreenState();
}

class _RollPrintScreenState extends ConsumerState<RollPrintScreen> {
  bool _initialized = false;
  final _startPositionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeRoll();
    });
  }

  Future<void> _initializeRoll() async {
    await ref.read(rollPrintProvider.notifier).initializeRoll(widget.rollId);

    // If a start position was specified, update the controller
    final printState = ref.read(rollPrintProvider);
    if (widget.startFromPosition != null) {
      _startPositionController.text = widget.startFromPosition.toString();
    } else {
      _startPositionController.text = printState.currentPosition.toString();
    }

    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    ref.read(rollPrintProvider.notifier).stopPrinting();
    _startPositionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rollAsync = ref.watch(rfidTagRollByIdProvider(widget.rollId));
    final printState = ref.watch(rollPrintProvider);
    final niimbotState = ref.watch(niimbotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Print Labels'),
        actions: [
          // Printer status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildPrinterStatus(niimbotState),
          ),
        ],
      ),
      body: rollAsync.when(
        data: (roll) {
          if (roll == null) {
            return const ErrorState(
              message: 'Roll not found',
              details: 'This roll may have been deleted.',
            );
          }
          if (!_initialized) {
            return const LoadingIndicator();
          }
          return _buildContent(context, roll, printState, niimbotState);
        },
        loading: () => const LoadingIndicator(),
        error: (error, _) => ErrorState(
          message: 'Failed to load roll',
          details: error.toString(),
          onRetry: () =>
              ref.invalidate(rfidTagRollByIdProvider(widget.rollId)),
        ),
      ),
    );
  }

  Widget _buildPrinterStatus(NiimbotState niimbotState) {
    final isConnected = niimbotState.isConnected;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? SaturdayColors.success : SaturdayColors.error,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isConnected ? 'Printer Connected' : 'Printer Offline',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    RfidTagRoll roll,
    RollPrintState printState,
    NiimbotState niimbotState,
  ) {
    return Column(
      children: [
        // Status bar
        _buildStatusBar(context, roll, printState),

        // Error display
        if (printState.lastError != null)
          _buildErrorBanner(context, printState.lastError!),

        // Completion banner
        if (printState.isComplete) _buildCompleteBanner(context),

        // Main content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Progress card
                _buildProgressCard(context, roll, printState),

                const SizedBox(height: 16),

                // Current tag info
                if (printState.currentTag != null && printState.isPrinting)
                  _buildCurrentTagCard(context, printState),

                // Start position selector (only when not printing)
                if (!printState.isPrinting && !printState.isComplete)
                  _buildStartPositionCard(context, printState),

                const SizedBox(height: 16),

                // Printer connection (when not connected)
                if (!niimbotState.isConnected)
                  _buildConnectPrinterCard(context),
              ],
            ),
          ),
        ),

        // Action bar
        _buildActionBar(context, printState, niimbotState),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    RfidTagRoll roll,
    RollPrintState printState,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SaturdayColors.primaryDark,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Roll ${roll.shortId}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${roll.labelWidthMm.toStringAsFixed(0)} x ${roll.labelHeightMm.toStringAsFixed(0)} mm',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (printState.currentOperation != null)
            Text(
              printState.currentOperation!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String error) {
    final printState = ref.watch(rollPrintProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SaturdayColors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: SaturdayColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error, style: TextStyle(color: SaturdayColors.error)),
          ),
          if (printState.isPaused) ...[
            TextButton(
              onPressed: () {
                ref.read(rollPrintProvider.notifier).retryCurrentTag();
              },
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: () {
                ref.read(rollPrintProvider.notifier).skipCurrentTag();
              },
              child: const Text('Skip'),
            ),
          ] else
            IconButton(
              icon: Icon(Icons.close, color: SaturdayColors.error, size: 20),
              onPressed: () {
                ref.read(rollPrintProvider.notifier).clearError();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildCompleteBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SaturdayColors.success.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: SaturdayColors.success, size: 20),
          const SizedBox(width: 8),
          Text(
            'Print job complete!',
            style: TextStyle(
              color: SaturdayColors.success,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(
    BuildContext context,
    RfidTagRoll roll,
    RollPrintState printState,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print, color: SaturdayColors.primaryDark),
                const SizedBox(width: 8),
                Text(
                  'Print Progress',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress stats
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn(
                    'Current',
                    '${printState.currentPosition}',
                  ),
                ),
                Container(width: 1, height: 50, color: SaturdayColors.light),
                Expanded(
                  child: _buildStatColumn(
                    'Printed',
                    '${printState.printedCount}',
                    color: SaturdayColors.success,
                  ),
                ),
                Container(width: 1, height: 50, color: SaturdayColors.light),
                Expanded(
                  child: _buildStatColumn(
                    'Failed',
                    '${printState.failedCount}',
                    color: printState.failedCount > 0
                        ? SaturdayColors.error
                        : null,
                  ),
                ),
                Container(width: 1, height: 50, color: SaturdayColors.light),
                Expanded(
                  child: _buildStatColumn(
                    'Total',
                    '${printState.totalTags}',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: printState.progress,
                backgroundColor: SaturdayColors.light,
                valueColor:
                    AlwaysStoppedAnimation<Color>(SaturdayColors.success),
                minHeight: 8,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '${(printState.progress * 100).toStringAsFixed(1)}% complete',
              style: TextStyle(
                fontSize: 12,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: SaturdayColors.secondaryGrey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color ?? SaturdayColors.primaryDark,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentTagCard(BuildContext context, RollPrintState printState) {
    final tag = printState.currentTag;
    if (tag == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.label, color: SaturdayColors.info),
                const SizedBox(width: 8),
                Text(
                  'Now Printing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Position ${tag.rollPosition}',
              style: TextStyle(
                fontSize: 12,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tag.formattedEpc,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartPositionCard(
    BuildContext context,
    RollPrintState printState,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.first_page, color: SaturdayColors.primaryDark),
                const SizedBox(width: 8),
                Text(
                  'Start Position',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Choose which label position to start printing from:',
              style: TextStyle(
                fontSize: 14,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startPositionController,
                    decoration: const InputDecoration(
                      labelText: 'Position',
                      hintText: '1',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'of ${printState.totalTags}',
                  style: TextStyle(
                    fontSize: 14,
                    color: SaturdayColors.secondaryGrey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectPrinterCard(BuildContext context) {
    final ports = ref.watch(availableNiimbotPortsProvider);

    return Card(
      color: SaturdayColors.error.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print_disabled, color: SaturdayColors.error),
                const SizedBox(width: 8),
                Text(
                  'Printer Not Connected',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: SaturdayColors.error,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Connect to a Niimbot printer to start printing.',
              style: TextStyle(color: SaturdayColors.secondaryGrey),
            ),
            if (ports.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Available ports:',
                style: TextStyle(
                  fontSize: 12,
                  color: SaturdayColors.secondaryGrey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ports.map((port) {
                  return ActionChip(
                    label: Text(port),
                    onPressed: () async {
                      await ref.read(niimbotProvider.notifier).connect(port);
                    },
                  );
                }).toList(),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'No serial ports detected. Make sure the printer is connected via USB.',
                style: TextStyle(
                  fontSize: 12,
                  color: SaturdayColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context,
    RollPrintState printState,
    NiimbotState niimbotState,
  ) {
    final isPrinterConnected = niimbotState.isConnected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Back button
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const SizedBox(width: 12),

            // Main action button(s)
            Expanded(
              child: _buildMainActionButton(
                printState,
                isPrinterConnected,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainActionButton(
    RollPrintState printState,
    bool isPrinterConnected,
  ) {
    if (printState.isComplete) {
      return FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.check),
        label: const Text('Done'),
        style: FilledButton.styleFrom(
          backgroundColor: SaturdayColors.success,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      );
    }

    if (!printState.isPrinting) {
      // Start button
      return FilledButton.icon(
        onPressed: isPrinterConnected
            ? () {
                final positionText = _startPositionController.text;
                final position = int.tryParse(positionText);
                if (position != null && position >= 1) {
                  ref
                      .read(rollPrintProvider.notifier)
                      .startFromPosition(position);
                } else {
                  ref.read(rollPrintProvider.notifier).startPrinting();
                }
              }
            : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start Printing'),
        style: FilledButton.styleFrom(
          backgroundColor: SaturdayColors.primaryDark,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      );
    }

    // Printing controls
    return Row(
      children: [
        // Stop button
        OutlinedButton.icon(
          onPressed: () {
            ref.read(rollPrintProvider.notifier).stopPrinting();
          },
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
          style: OutlinedButton.styleFrom(
            foregroundColor: SaturdayColors.error,
          ),
        ),
        const SizedBox(width: 12),

        // Pause/Resume button
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              if (printState.isPaused) {
                ref.read(rollPrintProvider.notifier).resumePrinting();
              } else {
                ref.read(rollPrintProvider.notifier).pausePrinting();
              }
            },
            icon: Icon(printState.isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(printState.isPaused ? 'Resume' : 'Pause'),
            style: FilledButton.styleFrom(
              backgroundColor: printState.isPaused
                  ? SaturdayColors.success
                  : SaturdayColors.info,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
