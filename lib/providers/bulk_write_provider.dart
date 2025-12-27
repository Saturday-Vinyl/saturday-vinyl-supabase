import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Flag to prevent concurrent tag processing
  bool _isProcessingTag = false;

  /// Cache of EPCs we've already processed this session (avoids repeated DB lookups)
  final Set<String> _processedEpcs = {};

  /// Timeout for no new tags found
  static const _noTagTimeout = Duration(seconds: 3);

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

    // Reset processing flag and cache
    _isProcessingTag = false;
    _processedEpcs.clear();

    // Reset state
    state = const BulkWriteState(
      isWriting: true,
      currentOperation: 'Searching for tags...',
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

    // Ignore if already processing a tag (prevent concurrent writes)
    if (_isProcessingTag) {
      return;
    }

    final epc = result.epcHex.toUpperCase();

    // Skip if we've already processed this EPC this session
    if (_processedEpcs.contains(epc)) {
      return;
    }

    // Cancel no-tag timer since we found a NEW tag
    _noTagTimer?.cancel();

    // Mark as processing to prevent concurrent calls
    _isProcessingTag = true;

    try {
      if (result.isSaturdayTag) {
        // This is already a Saturday tag - ensure it's in the database
        await _ensureSaturdayTagInDatabase(result);
      } else {
        // This is an unwritten tag - write Saturday EPC and add to database
        await _processUnwrittenTag(result);
      }
      // Mark this EPC as processed (whether it needed action or not)
      _processedEpcs.add(epc);
    } finally {
      _isProcessingTag = false;
    }

    // If still writing and not stopped, reset timer for next tag
    if (state.isWriting && !state.stopRequested) {
      _resetNoTagTimer();
    }
  }

  /// Ensure a Saturday tag exists in the database (idempotent)
  Future<void> _ensureSaturdayTagInDatabase(TagPollResult result) async {
    final tagRepo = _ref.read(rfidTagRepositoryProvider);

    final epc = result.epcHex.toUpperCase();

    // Check if tag already exists in database
    final existingTag = await tagRepo.getTagByEpc(epc);
    if (existingTag != null) {
      // Tag already in database, nothing to do
      AppLogger.debug('BulkWrite: Saturday tag $epc already in database');
      return;
    }

    // Tag not in database - add it
    final activityLog = _ref.read(activityLogProvider.notifier);
    AppLogger.info('BulkWrite: Found Saturday tag not in database: ${result.formattedEpc}');
    activityLog.info('Found existing Saturday tag, adding to database...');

    state = state.copyWith(currentOperation: 'Adding existing tag to database...');

    final currentUser = await _ref.read(currentUserProvider.future);

    try {
      await tagRepo.createAndWriteTag(
        epc: epc,
        createdBy: currentUser?.id,
      );

      activityLog.success('Added existing tag: ${result.formattedEpc}', relatedEpc: epc);

      state = state.copyWith(
        tagsWritten: state.tagsWritten + 1,
        currentOperation: 'Searching for tags...',
      );

      // Refresh the tags list
      _ref.invalidate(filteredRfidTagsProvider);
    } catch (e) {
      // If insert fails (e.g., race condition duplicate), just log and continue
      AppLogger.warning('BulkWrite: Failed to add existing tag (may already exist): $e');
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
      // Write failed - log the error but continue with other tags
      // This can happen if the tag is locked or has an access password mismatch
      AppLogger.warning('BulkWrite: Write failed for tag ${result.formattedEpc} (may be locked)');
      activityLog.error('Write failed for tag (may be locked or password protected)');

      // Resume polling and continue searching for other tags
      final uhfService = _ref.read(uhfRfidServiceProvider);
      if (state.isWriting && !state.stopRequested) {
        await uhfService.startPolling();
      }
      return;
    }

    // Note: Write command success response from M100 confirms the write worked.
    // The module only returns success (command=0x49) if the EPC was actually written.
    // Separate verification via polling is skipped to avoid timeout issues with
    // multiple tags in the field.
    activityLog.success('Write successful', relatedEpc: newEpc);

    // Note: Lock step is skipped in bulk write mode.
    // The M100 module cannot reliably target a specific tag for locking when
    // multiple tags are in the field. The lock command operates on whichever
    // tag responds first, which may not be the tag we just wrote.
    // Tags are saved as 'written' status. Locking can be done separately
    // with single-tag operations if needed.

    // Step 3: Save to database (as written, not locked)
    state = state.copyWith(currentOperation: 'Saving to database...');
    final saveSuccess = await _saveToDatabase(newEpc, status: RfidTagStatus.written);
    if (!saveSuccess) {
      await _handleError('Database save failed');
      return;
    }

    // Success!
    activityLog.success('Tag written and saved: $formattedEpc', relatedEpc: newEpc);

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

    // Small delay to let the module settle after stopping polling
    // This ensures any pending responses are cleared before the write
    await Future.delayed(const Duration(milliseconds: 100));

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

  /// Save the tag to the database (idempotent - checks if exists first)
  Future<bool> _saveToDatabase(String epcHex, {required RfidTagStatus status}) async {
    try {
      final tagRepo = _ref.read(rfidTagRepositoryProvider);
      final normalizedEpc = epcHex.toUpperCase();

      // Check if tag already exists (idempotent)
      final existingTag = await tagRepo.getTagByEpc(normalizedEpc);
      if (existingTag != null) {
        AppLogger.info('BulkWrite: Tag $normalizedEpc already in database');
        return true;
      }

      final currentUser = await _ref.read(currentUserProvider.future);

      // Create with written status
      await tagRepo.createAndWriteTag(
        epc: normalizedEpc,
        createdBy: currentUser?.id,
      );

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

    if (reason.isNotEmpty && !reason.contains('No new tags')) {
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
        AppLogger.info('BulkWrite: No new tags found for ${_noTagTimeout.inSeconds}s, processed ${_processedEpcs.length} total');
        _stopWriting('No new tags found');
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
