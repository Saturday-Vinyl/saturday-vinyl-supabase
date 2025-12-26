import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/env_config.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/tag_poll_result.dart';
import 'package:saturday_app/providers/activity_log_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/rfid_tag_provider.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// State for bulk write mode
class BulkWriteState {
  /// Whether bulk writing is currently active
  final bool isWriting;

  /// Number of tags successfully written in this session
  final int tagsWritten;

  /// Current operation being performed
  final String? currentOperation;

  /// Last error encountered
  final String? lastError;

  /// Whether user has requested to stop
  final bool stopRequested;

  const BulkWriteState({
    this.isWriting = false,
    this.tagsWritten = 0,
    this.currentOperation,
    this.lastError,
    this.stopRequested = false,
  });

  BulkWriteState copyWith({
    bool? isWriting,
    int? tagsWritten,
    String? currentOperation,
    String? lastError,
    bool? stopRequested,
    bool clearOperation = false,
    bool clearError = false,
  }) {
    return BulkWriteState(
      isWriting: isWriting ?? this.isWriting,
      tagsWritten: tagsWritten ?? this.tagsWritten,
      currentOperation:
          clearOperation ? null : (currentOperation ?? this.currentOperation),
      lastError: clearError ? null : (lastError ?? this.lastError),
      stopRequested: stopRequested ?? this.stopRequested,
    );
  }

  @override
  String toString() =>
      'BulkWriteState(writing: $isWriting, written: $tagsWritten, op: $currentOperation)';
}

/// Notifier for managing bulk write operations
class BulkWriteNotifier extends StateNotifier<BulkWriteState> {
  final Ref _ref;
  StreamSubscription<TagPollResult>? _pollSubscription;
  Timer? _noTagTimer;

  /// Timeout for no unwritten tags found
  static const _noTagTimeout = Duration(seconds: 2);

  BulkWriteNotifier(this._ref) : super(const BulkWriteState());

  /// Start bulk write mode
  Future<bool> startBulkWrite() async {
    if (state.isWriting) {
      AppLogger.warning('BulkWrite: Already writing');
      return true;
    }

    final uhfService = _ref.read(uhfRfidServiceProvider);
    final activityLog = _ref.read(activityLogProvider.notifier);

    if (!uhfService.isConnected) {
      const error = 'RFID module not connected';
      state = state.copyWith(lastError: error);
      activityLog.error(error);
      AppLogger.warning('BulkWrite: $error');
      return false;
    }

    AppLogger.info('BulkWrite: Starting bulk write mode');
    activityLog.info('Starting bulk write mode...');

    // Reset state
    state = BulkWriteState(
      isWriting: true,
      currentOperation: 'Searching for unwritten tags...',
    );

    // Start polling
    final success = await uhfService.startPolling();
    if (!success) {
      const error = 'Failed to start polling';
      state = state.copyWith(isWriting: false, lastError: error);
      activityLog.error(error);
      return false;
    }

    // Subscribe to poll results
    _pollSubscription = uhfService.pollStream.listen(_onTagDetected);

    // Start no-tag timeout
    _resetNoTagTimer();

    return true;
  }

  /// Request to stop bulk write (will stop after current operation)
  void stopBulkWrite() {
    if (!state.isWriting) return;

    AppLogger.info('BulkWrite: Stop requested');
    state = state.copyWith(stopRequested: true);
  }

  /// Handle a detected tag
  Future<void> _onTagDetected(TagPollResult result) async {
    // Ignore if not writing or stop requested
    if (!state.isWriting || state.stopRequested) return;

    // Only process unwritten tags (those without Saturday prefix)
    if (result.isSaturdayTag) {
      // This is already a Saturday tag, skip it
      return;
    }

    // Cancel no-tag timer since we found one
    _noTagTimer?.cancel();

    // Process this unwritten tag
    await _processUnwrittenTag(result);

    // If still writing and not stopped, reset timer for next tag
    if (state.isWriting && !state.stopRequested) {
      _resetNoTagTimer();
    }
  }

  /// Process an unwritten tag through the full write workflow
  Future<void> _processUnwrittenTag(TagPollResult result) async {
    final activityLog = _ref.read(activityLogProvider.notifier);

    AppLogger.info('BulkWrite: Found unwritten tag: ${result.formattedEpc}');
    activityLog.info('Found unwritten tag, generating EPC...');

    // Generate new EPC
    final newEpc = RfidTag.generateEpc();
    final formattedEpc = _formatEpc(newEpc);

    AppLogger.info('BulkWrite: Generated EPC: $formattedEpc');

    // Step 1: Write EPC
    state = state.copyWith(currentOperation: 'Writing EPC $formattedEpc...');
    activityLog.info('Writing EPC $formattedEpc to tag', relatedEpc: newEpc);

    final writeSuccess = await _writeTag(newEpc);
    if (!writeSuccess) {
      await _handleError('Write failed');
      return;
    }

    // Step 2: Verify write
    state = state.copyWith(currentOperation: 'Verifying write...');
    activityLog.info('Verifying write...', relatedEpc: newEpc);

    final verifySuccess = await _verifyWrite(newEpc);
    if (!verifySuccess) {
      await _handleError('Write verification failed');
      return;
    }

    activityLog.success('Write verified successfully', relatedEpc: newEpc);

    // Step 3: Lock tag
    state = state.copyWith(currentOperation: 'Locking tag...');
    activityLog.info('Locking tag...', relatedEpc: newEpc);

    final lockSuccess = await _lockTag();
    if (!lockSuccess) {
      // Lock failed, but write succeeded - save as 'written' status
      await _saveToDatabase(newEpc, status: RfidTagStatus.written);
      await _handleError('Lock failed (tag saved as written)');
      return;
    }

    // Step 4: Save to database
    state = state.copyWith(currentOperation: 'Saving to database...');
    final saveSuccess = await _saveToDatabase(newEpc, status: RfidTagStatus.locked);
    if (!saveSuccess) {
      await _handleError('Database save failed');
      return;
    }

    // Success!
    activityLog.success('Tag locked and saved: $formattedEpc', relatedEpc: newEpc);

    state = state.copyWith(
      tagsWritten: state.tagsWritten + 1,
      currentOperation: 'Searching for unwritten tags...',
    );

    // Refresh the tags list to show the new tag
    _ref.invalidate(filteredRfidTagsProvider);
  }

  /// Write EPC to the tag
  Future<bool> _writeTag(String epcHex) async {
    final uhfService = _ref.read(uhfRfidServiceProvider);

    // Convert hex string to bytes
    final epcBytes = _hexToBytes(epcHex);

    // Stop polling during write
    await uhfService.stopPolling();

    try {
      final result = await uhfService.writeEpc(epcBytes);
      return result.success;
    } finally {
      // Resume polling
      if (state.isWriting && !state.stopRequested) {
        await uhfService.startPolling();
      }
    }
  }

  /// Verify the EPC was written correctly
  Future<bool> _verifyWrite(String epcHex) async {
    final uhfService = _ref.read(uhfRfidServiceProvider);

    // Convert hex string to bytes
    final epcBytes = _hexToBytes(epcHex);

    return await uhfService.verifyEpc(
      epcBytes,
      timeout: const Duration(seconds: 2),
    );
  }

  /// Lock the tag with access password
  Future<bool> _lockTag() async {
    final uhfService = _ref.read(uhfRfidServiceProvider);

    // Get access password from environment config (shared across all devices)
    final passwordBytes = EnvConfig.rfidAccessPasswordBytes;

    // Stop polling during lock
    await uhfService.stopPolling();

    try {
      final result = await uhfService.lockTag(passwordBytes);
      return result.success;
    } finally {
      // Resume polling
      if (state.isWriting && !state.stopRequested) {
        await uhfService.startPolling();
      }
    }
  }

  /// Save the tag to the database
  Future<bool> _saveToDatabase(String epcHex, {required RfidTagStatus status}) async {
    try {
      final tagRepo = _ref.read(rfidTagRepositoryProvider);
      final currentUser = await _ref.read(currentUserProvider.future);

      if (status == RfidTagStatus.locked) {
        // Create with locked status (includes written_at and locked_at)
        await tagRepo.createAndWriteTag(
          epc: epcHex,
          createdBy: currentUser?.id,
        );
        // Then update to locked
        final tag = await tagRepo.getTagByEpc(epcHex);
        if (tag != null) {
          await tagRepo.updateTagStatus(tag.id, RfidTagStatus.locked);
        }
      } else {
        // Create with written status
        await tagRepo.createAndWriteTag(
          epc: epcHex,
          createdBy: currentUser?.id,
        );
      }

      return true;
    } catch (e) {
      AppLogger.error('BulkWrite: Database save failed', e);
      return false;
    }
  }

  /// Handle an error during the write process
  Future<void> _handleError(String message) async {
    final activityLog = _ref.read(activityLogProvider.notifier);

    AppLogger.error('BulkWrite: $message');
    activityLog.error('ERROR: $message');

    // Stop the bulk write process on any error
    await _stopWriting('Error: $message');
  }

  /// Stop the writing process
  Future<void> _stopWriting(String reason) async {
    final uhfService = _ref.read(uhfRfidServiceProvider);
    final activityLog = _ref.read(activityLogProvider.notifier);

    // Cancel subscriptions and timers
    _noTagTimer?.cancel();
    await _pollSubscription?.cancel();
    _pollSubscription = null;

    // Stop polling
    await uhfService.stopPolling();

    // Log completion
    if (state.tagsWritten > 0 || !reason.startsWith('Error')) {
      activityLog.info(
        'Bulk write complete: ${state.tagsWritten} tag${state.tagsWritten == 1 ? '' : 's'} created',
      );
    }

    if (reason.isNotEmpty && !reason.contains('No unwritten tags')) {
      activityLog.info('Stopping bulk write: $reason');
    }

    state = state.copyWith(
      isWriting: false,
      currentOperation: null,
      stopRequested: false,
      lastError: reason.startsWith('Error') ? reason : null,
    );
  }

  /// Reset the no-tag timeout timer
  void _resetNoTagTimer() {
    _noTagTimer?.cancel();
    _noTagTimer = Timer(_noTagTimeout, () {
      if (state.isWriting && !state.stopRequested) {
        AppLogger.info('BulkWrite: No unwritten tags found for ${_noTagTimeout.inSeconds}s');
        _stopWriting('No unwritten tags found');
      }
    });
  }

  /// Convert hex string to bytes
  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// Format EPC for display
  String _formatEpc(String hex) {
    final upper = hex.toUpperCase();
    if (upper.length != 24) return upper;
    return '${upper.substring(0, 4)}-${upper.substring(4, 8)}-${upper.substring(8, 12)}-${upper.substring(12, 16)}-${upper.substring(16, 20)}-${upper.substring(20, 24)}';
  }

  @override
  void dispose() {
    _noTagTimer?.cancel();
    _pollSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for bulk write state and control
final bulkWriteProvider =
    StateNotifierProvider<BulkWriteNotifier, BulkWriteState>((ref) {
  final notifier = BulkWriteNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

/// Provider for checking if bulk write is active
final isBulkWritingProvider = Provider<bool>((ref) {
  return ref.watch(bulkWriteProvider).isWriting;
});
