import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/providers/rfid_tag_roll_provider.dart';
import 'package:saturday_app/providers/roll_write_provider.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/tags/rfid_module_status.dart';
import 'package:saturday_app/widgets/tags/rssi_tag_list.dart';

/// Screen for writing RFID tags to a roll using RSSI-based identification
///
/// Shows detected tags sorted by signal strength. The user writes to
/// the "active" tag (strongest unwritten signal) one at a time,
/// advancing the position counter after each successful write.
class RollWriteScreen extends ConsumerStatefulWidget {
  final String rollId;

  const RollWriteScreen({super.key, required this.rollId});

  @override
  ConsumerState<RollWriteScreen> createState() => _RollWriteScreenState();
}

class _RollWriteScreenState extends ConsumerState<RollWriteScreen> {
  bool _initialized = false;
  int _rfPower = RfidConfig.defaultRfPower;

  @override
  void initState() {
    super.initState();
    // Initialize the roll write provider after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeRoll();
    });
  }

  Future<void> _initializeRoll() async {
    await ref.read(rollWriteProvider.notifier).initializeRoll(widget.rollId);
    // Get current RF power
    final power = await ref.read(rollWriteProvider.notifier).getRfPower();
    setState(() {
      _initialized = true;
      if (power != null) _rfPower = power;
    });
  }

  @override
  void dispose() {
    // Stop scanning when leaving the screen
    ref.read(rollWriteProvider.notifier).stopScanning();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rollAsync = ref.watch(rfidTagRollByIdProvider(widget.rollId));
    final rollWriteState = ref.watch(rollWriteProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Write Tags'),
        actions: const [
          RfidAppBarStatus(),
          SizedBox(width: 8),
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
          return _buildContent(context, roll, rollWriteState);
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

  Widget _buildContent(
    BuildContext context,
    RfidTagRoll roll,
    RollWriteState writeState,
  ) {
    return Column(
      children: [
        // Status bar
        _buildStatusBar(context, roll, writeState),

        // Error display
        if (writeState.lastError != null)
          _buildErrorBanner(context, writeState.lastError!),

        // Success flash
        if (writeState.writeSuccess) _buildSuccessBanner(context),

        // Main content area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Progress card
                _buildProgressCard(context, roll, writeState),

                const SizedBox(height: 16),

                // RF Power control card
                _buildRfPowerCard(context, writeState),

                const SizedBox(height: 16),

                // RSSI tag list
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.sensors,
                              color: writeState.isScanning
                                  ? SaturdayColors.info
                                  : SaturdayColors.secondaryGrey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Detected Tags',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (writeState.isScanning)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      SaturdayColors.info.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: SaturdayColors.info,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Scanning',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: SaturdayColors.info,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const RssiTagList(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom action bar
        _buildActionBar(context, roll, writeState),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    RfidTagRoll roll,
    RollWriteState writeState,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SaturdayColors.primaryDark,
      child: Row(
        children: [
          // Roll info
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
          // Current operation
          if (writeState.currentOperation != null)
            Text(
              writeState.currentOperation!,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SaturdayColors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: SaturdayColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: SaturdayColors.error, size: 20),
            onPressed: () {
              ref.read(rollWriteProvider.notifier).clearError();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(BuildContext context) {
    // Auto-clear after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        ref.read(rollWriteProvider.notifier).clearWriteSuccess();
      }
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: SaturdayColors.success.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: SaturdayColors.success, size: 20),
          const SizedBox(width: 8),
          Text(
            'Tag written successfully!',
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
    RollWriteState writeState,
  ) {
    final tagCountAsync = ref.watch(tagCountForRollProvider(widget.rollId));
    final tagsWritten = tagCountAsync.valueOrNull ?? 0;
    final progress = roll.labelCount > 0 ? tagsWritten / roll.labelCount : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.linear_scale, color: SaturdayColors.primaryDark),
                const SizedBox(width: 8),
                Text(
                  'Writing Progress',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Position indicator
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Next Position',
                        style: TextStyle(
                          fontSize: 12,
                          color: SaturdayColors.secondaryGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${writeState.currentPosition}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: SaturdayColors.light,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tags Written',
                        style: TextStyle(
                          fontSize: 12,
                          color: SaturdayColors.secondaryGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$tagsWritten / ${roll.labelCount}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: SaturdayColors.light,
                valueColor:
                    AlwaysStoppedAnimation<Color>(SaturdayColors.success),
                minHeight: 8,
              ),
            ),

            const SizedBox(height: 8),

            // Percentage
            Text(
              '${(progress * 100).toStringAsFixed(1)}% complete',
              style: TextStyle(
                fontSize: 12,
                color: SaturdayColors.secondaryGrey,
              ),
            ),

            // All tags written indicator
            if (writeState.allTagsWritten && writeState.isScanning) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SaturdayColors.success),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: SaturdayColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'All visible tags have been written!',
                        style: TextStyle(color: SaturdayColors.success),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRfPowerCard(BuildContext context, RollWriteState writeState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering, color: SaturdayColors.primaryDark),
                const SizedBox(width: 8),
                Text(
                  'RF Power',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$_rfPower dBm',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SaturdayColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Lower power helps isolate single tags when writing. Start low and increase if no tags are detected.',
              style: TextStyle(
                fontSize: 12,
                color: SaturdayColors.secondaryGrey,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${RfidConfig.minRfPower}',
                  style: TextStyle(
                    fontSize: 12,
                    color: SaturdayColors.secondaryGrey,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _rfPower.toDouble(),
                    min: RfidConfig.minRfPower.toDouble(),
                    max: RfidConfig.maxRfPower.toDouble(),
                    divisions: RfidConfig.maxRfPower - RfidConfig.minRfPower,
                    onChanged: writeState.isWriting
                        ? null
                        : (value) {
                            setState(() {
                              _rfPower = value.round();
                            });
                          },
                    onChangeEnd: writeState.isWriting
                        ? null
                        : (value) async {
                            final success = await ref
                                .read(rollWriteProvider.notifier)
                                .setRfPower(value.round());
                            if (!success && mounted) {
                              // Revert if failed
                              final current = await ref
                                  .read(rollWriteProvider.notifier)
                                  .getRfPower();
                              if (current != null && mounted) {
                                setState(() {
                                  _rfPower = current;
                                });
                              }
                            }
                          },
                  ),
                ),
                Text(
                  '${RfidConfig.maxRfPower}',
                  style: TextStyle(
                    fontSize: 12,
                    color: SaturdayColors.secondaryGrey,
                  ),
                ),
              ],
            ),
            // Power level indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildPowerIndicator('Low', _rfPower <= 10),
                _buildPowerIndicator('Medium', _rfPower > 10 && _rfPower <= 20),
                _buildPowerIndicator('High', _rfPower > 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerIndicator(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? SaturdayColors.info.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? SaturdayColors.info : SaturdayColors.light,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? SaturdayColors.info : SaturdayColors.secondaryGrey,
        ),
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context,
    RfidTagRoll roll,
    RollWriteState writeState,
  ) {
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
            // Scan toggle button
            if (!writeState.isScanning)
              Expanded(
                child: FilledButton.icon(
                  onPressed: writeState.isWriting
                      ? null
                      : () {
                          ref.read(rollWriteProvider.notifier).startScanning();
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Scanning'),
                  style: FilledButton.styleFrom(
                    backgroundColor: SaturdayColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              )
            else ...[
              // Stop button
              OutlinedButton.icon(
                onPressed: writeState.isWriting
                    ? null
                    : () {
                        ref.read(rollWriteProvider.notifier).stopScanning();
                      },
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              const SizedBox(width: 12),

              // Write button
              Expanded(
                child: FilledButton.icon(
                  onPressed: (writeState.activeTag != null &&
                          !writeState.isWriting)
                      ? () {
                          ref
                              .read(rollWriteProvider.notifier)
                              .writeToActiveTag();
                        }
                      : null,
                  icon: writeState.isWriting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        )
                      : const Icon(Icons.edit),
                  label: Text(
                    writeState.isWriting
                        ? 'Writing...'
                        : writeState.activeTag != null
                            ? 'Write to Active Tag'
                            : 'No Unwritten Tag',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: writeState.activeTag != null
                        ? SaturdayColors.info
                        : SaturdayColors.secondaryGrey,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],

            // Finish button (when writing complete)
            if (writeState.isScanning && writeState.allTagsWritten) ...[
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final success = await ref
                      .read(rollWriteProvider.notifier)
                      .finishWriting();
                  if (success && mounted) {
                    navigator.pop();
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Finish'),
                style: FilledButton.styleFrom(
                  backgroundColor: SaturdayColors.success,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
