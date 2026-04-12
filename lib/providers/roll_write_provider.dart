import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/models/tag_poll_result.dart';
import 'package:saturday_app/providers/activity_log_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/rfid_tag_provider.dart';
import 'package:saturday_app/providers/rfid_tag_roll_provider.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Sentinel value for distinguishing "not provided" from explicit null in copyWith
const _sentinel = Object();

/// Represents a tag detected during roll writing with its signal strength
class DetectedTag {
  final String epcHex;
  final String formattedEpc;
  final int rssi;
  final int signalStrength; // 0-100 percentage (instantaneous)
  final double smoothedRssi; // EMA-smoothed signed RSSI
  final int readCount; // number of readings accumulated
  final bool isSaturdayTag;
  final bool isInDatabase;
  final DateTime lastSeen;

  const DetectedTag({
    required this.epcHex,
    required this.formattedEpc,
    required this.rssi,
    required this.signalStrength,
    required this.smoothedRssi,
    this.readCount = 1,
    required this.isSaturdayTag,
    required this.isInDatabase,
    required this.lastSeen,
  });

  /// Signal strength (0-100) derived from the smoothed RSSI EMA
  int get smoothedSignalStrength {
    const minRssi = -80.0;
    const maxRssi = -20.0;
    final clamped = smoothedRssi.clamp(minRssi, maxRssi);
    return ((clamped - minRssi) / (maxRssi - minRssi) * 100).round();
  }

  DetectedTag copyWith({
    String? epcHex,
    String? formattedEpc,
    int? rssi,
    int? signalStrength,
    double? smoothedRssi,
    int? readCount,
    bool? isSaturdayTag,
    bool? isInDatabase,
    DateTime? lastSeen,
  }) {
    return DetectedTag(
      epcHex: epcHex ?? this.epcHex,
      formattedEpc: formattedEpc ?? this.formattedEpc,
      rssi: rssi ?? this.rssi,
      signalStrength: signalStrength ?? this.signalStrength,
      smoothedRssi: smoothedRssi ?? this.smoothedRssi,
      readCount: readCount ?? this.readCount,
      isSaturdayTag: isSaturdayTag ?? this.isSaturdayTag,
      isInDatabase: isInDatabase ?? this.isInDatabase,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// State for roll write mode
class RollWriteState {
  /// The roll being written to
  final RfidTagRoll? roll;

  /// Whether scanning is active
  final bool isScanning;

  /// Whether a write operation is in progress
  final bool isWriting;

  /// Current position on the roll (next position to write)
  final int currentPosition;

  /// Tags currently detected, sorted by smoothed signal strength (strongest first)
  final List<DetectedTag> detectedTags;

  /// EPC of the current focus tag (center slot — write candidate)
  final String? focusTagEpc;

  /// EPC of the previous focus tag (left slot — last written or previously focused)
  final String? previousFocusTagEpc;

  /// Current operation description
  final String? currentOperation;

  /// Last error encountered
  final String? lastError;

  /// Whether write was successful (for showing success state)
  final bool writeSuccess;

  const RollWriteState({
    this.roll,
    this.isScanning = false,
    this.isWriting = false,
    this.currentPosition = 1,
    this.detectedTags = const [],
    this.focusTagEpc,
    this.previousFocusTagEpc,
    this.currentOperation,
    this.lastError,
    this.writeSuccess = false,
  });

  /// The focus tag (center slot — strongest smoothed RSSI, any tag)
  DetectedTag? get activeTag {
    if (focusTagEpc == null) return null;
    for (final tag in detectedTags) {
      if (tag.epcHex == focusTagEpc) return tag;
    }
    return null;
  }

  /// The previous tag (left slot — was previously in focus, now dropping RSSI)
  DetectedTag? get previousTag {
    if (previousFocusTagEpc == null) return null;
    // Never show the same tag in both previous and focus slots
    if (previousFocusTagEpc == focusTagEpc) return null;
    for (final tag in detectedTags) {
      if (tag.epcHex == previousFocusTagEpc) return tag;
    }
    return null;
  }

  /// The next tag (right slot — strongest tag that isn't focus or previous)
  DetectedTag? get nextTag {
    for (final tag in detectedTags) {
      if (tag.epcHex != focusTagEpc &&
          tag.epcHex != previousFocusTagEpc) {
        return tag;
      }
    }
    return null;
  }

  /// The strongest unwritten tag (for the write button)
  DetectedTag? get writeCandidateTag {
    for (final tag in detectedTags) {
      if (!tag.isSaturdayTag) return tag;
    }
    return null;
  }

  /// Check if all visible tags are Saturday tags (roll may be complete)
  bool get allTagsWritten {
    if (detectedTags.isEmpty) return false;
    return detectedTags.every((tag) => tag.isSaturdayTag);
  }

  RollWriteState copyWith({
    RfidTagRoll? roll,
    bool? isScanning,
    bool? isWriting,
    int? currentPosition,
    List<DetectedTag>? detectedTags,
    Object? focusTagEpc = _sentinel,
    Object? previousFocusTagEpc = _sentinel,
    String? currentOperation,
    String? lastError,
    bool? writeSuccess,
    bool clearOperation = false,
    bool clearError = false,
    bool clearRoll = false,
  }) {
    return RollWriteState(
      roll: clearRoll ? null : (roll ?? this.roll),
      isScanning: isScanning ?? this.isScanning,
      isWriting: isWriting ?? this.isWriting,
      currentPosition: currentPosition ?? this.currentPosition,
      detectedTags: detectedTags ?? this.detectedTags,
      focusTagEpc: focusTagEpc == _sentinel
          ? this.focusTagEpc
          : focusTagEpc as String?,
      previousFocusTagEpc: previousFocusTagEpc == _sentinel
          ? this.previousFocusTagEpc
          : previousFocusTagEpc as String?,
      currentOperation:
          clearOperation ? null : (currentOperation ?? this.currentOperation),
      lastError: clearError ? null : (lastError ?? this.lastError),
      writeSuccess: writeSuccess ?? this.writeSuccess,
    );
  }
}

/// Notifier for managing roll write operations
class RollWriteNotifier extends StateNotifier<RollWriteState> {
  final Ref _ref;
  StreamSubscription<TagPollResult>? _pollSubscription;
  Timer? _staleTagTimer;

  /// Map of EPC -> last seen time for tracking stale tags
  final Map<String, DateTime> _tagLastSeen = {};

  /// EPCs we know are in the database (cache to avoid repeated lookups)
  final Set<String> _knownDatabaseEpcs = {};

  /// Map of EPC -> smoothed signed RSSI (EMA)
  final Map<String, double> _tagSmoothedRssi = {};

  /// Map of EPC -> read count for EMA warmup
  final Map<String, int> _tagReadCount = {};

  /// EPC of the currently focused tag (center slot)
  String? _currentFocusEpc;

  /// EPC of the previously focused tag (left slot)
  String? _previousFocusEpc;

  /// EMA smoothing factor (0.3 = responsive but smooth)
  static const double _emaSmoothingFactor = 0.3;

  /// Minimum smoothed signal strength difference to swap focus tag (hysteresis)
  static const int _focusSwapThreshold = 10;

  /// How long before a tag is considered "stale" and removed from view
  static const _staleTagTimeout = Duration(seconds: 2);

  /// How often to check for stale tags
  static const _staleCheckInterval = Duration(milliseconds: 500);

  RollWriteNotifier(this._ref) : super(const RollWriteState());

  /// Initialize with a specific roll
  Future<void> initializeRoll(String rollId) async {
    AppLogger.info('RollWrite: Initializing for roll $rollId');

    // Load the roll
    final rollRepo = _ref.read(rfidTagRollRepositoryProvider);
    final roll = await rollRepo.getRollById(rollId);

    if (roll == null) {
      state = state.copyWith(lastError: 'Roll not found');
      return;
    }

    // Get the next position for this roll
    final nextPosition = await rollRepo.getNextPositionForRoll(rollId);

    // Load existing EPCs for this roll to avoid duplicates
    final existingTags = await rollRepo.getTagsForRoll(rollId);
    _knownDatabaseEpcs.clear();
    for (final tag in existingTags) {
      _knownDatabaseEpcs.add(tag.epcIdentifier.toUpperCase());
    }

    state = RollWriteState(
      roll: roll,
      currentPosition: nextPosition,
    );

    AppLogger.info(
      'RollWrite: Initialized roll ${roll.shortId}, next position: $nextPosition',
    );
  }

  /// Start scanning for tags
  Future<bool> startScanning() async {
    if (state.isScanning) {
      AppLogger.warning('RollWrite: Already scanning');
      return true;
    }

    if (state.roll == null) {
      state = state.copyWith(lastError: 'No roll selected');
      return false;
    }

    final uhfService = _ref.read(uhfRfidServiceProvider);
    final activityLog = _ref.read(activityLogProvider.notifier);

    if (!uhfService.isConnected) {
      const error = 'RFID module not connected';
      state = state.copyWith(lastError: error);
      activityLog.error(error);
      return false;
    }

    AppLogger.info('RollWrite: Starting tag scanning');
    activityLog.info('Starting tag scanning for roll...');

    // Clear previous state
    _tagLastSeen.clear();
    _tagSmoothedRssi.clear();
    _tagReadCount.clear();
    _currentFocusEpc = null;
    _previousFocusEpc = null;
    state = state.copyWith(
      isScanning: true,
      detectedTags: [],
      currentOperation: 'Scanning for tags...',
      clearError: true,
      focusTagEpc: null,
      previousFocusTagEpc: null,
      writeSuccess: false,
    );

    // Start polling
    final success = await uhfService.startPolling();
    if (!success) {
      const error = 'Failed to start polling';
      state = state.copyWith(isScanning: false, lastError: error);
      activityLog.error(error);
      return false;
    }

    // Subscribe to poll results
    _pollSubscription = uhfService.pollStream.listen(_onTagDetected);

    // Start stale tag cleanup timer
    _staleTagTimer = Timer.periodic(_staleCheckInterval, (_) {
      _removeStalesTags();
    });

    return true;
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    if (!state.isScanning) return;

    AppLogger.info('RollWrite: Stopping scanning');

    _staleTagTimer?.cancel();
    _staleTagTimer = null;

    await _pollSubscription?.cancel();
    _pollSubscription = null;

    final uhfService = _ref.read(uhfRfidServiceProvider);
    await uhfService.stopPolling();

    if (!mounted) return;
    state = state.copyWith(
      isScanning: false,
      clearOperation: true,
    );
  }

  /// Handle a detected tag with EMA smoothing and focus tracking
  Future<void> _onTagDetected(TagPollResult result) async {
    if (!mounted || !state.isScanning || state.isWriting) return;

    final epc = result.epcHex.toUpperCase();
    final now = DateTime.now();

    // Update last seen time
    _tagLastSeen[epc] = now;

    // Compute EMA-smoothed RSSI
    final signedRssi = result.rssi > 127
        ? (result.rssi - 256).toDouble()
        : result.rssi.toDouble();
    final prevSmoothed = _tagSmoothedRssi[epc];
    final count = (_tagReadCount[epc] ?? 0) + 1;
    _tagReadCount[epc] = count;

    final smoothed = prevSmoothed == null
        ? signedRssi
        : _emaSmoothingFactor * signedRssi +
            (1 - _emaSmoothingFactor) * prevSmoothed;
    _tagSmoothedRssi[epc] = smoothed;

    // Check if this is a Saturday tag
    final isSaturdayTag = result.isSaturdayTag;

    // Check if this is in our known database cache
    bool isInDatabase = _knownDatabaseEpcs.contains(epc);

    // If it's a Saturday tag but not in our cache, check the database
    if (isSaturdayTag && !isInDatabase) {
      if (!mounted) return;
      final tagRepo = _ref.read(rfidTagRepositoryProvider);
      final existingTag = await tagRepo.getTagByEpc(epc);
      if (!mounted) return;
      if (existingTag != null) {
        isInDatabase = true;
        _knownDatabaseEpcs.add(epc);
      }
    }

    if (!mounted) return;

    // Create or update the detected tag entry
    final detectedTag = DetectedTag(
      epcHex: epc,
      formattedEpc: result.formattedEpc,
      rssi: result.rssi,
      signalStrength: result.signalStrength,
      smoothedRssi: smoothed,
      readCount: count,
      isSaturdayTag: isSaturdayTag,
      isInDatabase: isInDatabase,
      lastSeen: now,
    );

    // Update the detected tags list
    final currentTags = List<DetectedTag>.from(state.detectedTags);
    final existingIndex = currentTags.indexWhere((t) => t.epcHex == epc);

    if (existingIndex >= 0) {
      currentTags[existingIndex] = detectedTag;
    } else {
      currentTags.add(detectedTag);
    }

    // Sort by smoothed signal strength (strongest first)
    currentTags
        .sort((a, b) => b.smoothedSignalStrength.compareTo(a.smoothedSignalStrength));

    // Focus tracking with hysteresis
    _updateFocusTracking(currentTags);

    if (!mounted) return;
    state = state.copyWith(
      detectedTags: currentTags,
      focusTagEpc: _currentFocusEpc,
      previousFocusTagEpc: _previousFocusEpc,
    );
  }

  /// Update focus tracking with hysteresis to prevent jitter.
  /// Focus is based purely on RSSI strength — any tag (written or not) can
  /// be the focus. Tags flow right -> center -> left as they cross the reader.
  void _updateFocusTracking(List<DetectedTag> sortedTags) {
    if (sortedTags.isEmpty) {
      if (_currentFocusEpc != null) {
        _previousFocusEpc = _currentFocusEpc;
      }
      _currentFocusEpc = null;
      return;
    }

    final strongest = sortedTags.first; // sorted by smoothedSignalStrength desc

    if (_currentFocusEpc == null ||
        _currentFocusEpc == strongest.epcHex) {
      // No current focus or same tag — keep it
      _currentFocusEpc = strongest.epcHex;
      // Clear previous if it's the same as current (tag returned to focus)
      if (_previousFocusEpc == _currentFocusEpc) {
        _previousFocusEpc = null;
      }
      return;
    }

    // Different tag is now strongest — check hysteresis
    final currentFocusTag =
        sortedTags.where((t) => t.epcHex == _currentFocusEpc).firstOrNull;

    if (currentFocusTag == null) {
      // Current focus tag is gone (stale) — swap immediately
      _previousFocusEpc = _currentFocusEpc;
      _currentFocusEpc = strongest.epcHex;
      return;
    }

    final diff = strongest.smoothedSignalStrength -
        currentFocusTag.smoothedSignalStrength;
    if (diff > _focusSwapThreshold) {
      _previousFocusEpc = _currentFocusEpc;
      _currentFocusEpc = strongest.epcHex;
    }
    // Otherwise keep current focus (hysteresis prevents jitter)
  }

  /// Remove tags that haven't been seen recently
  void _removeStalesTags() {
    if (!mounted) return;
    final now = DateTime.now();
    final staleCutoff = now.subtract(_staleTagTimeout);

    // Find stale EPCs
    final staleEpcs = _tagLastSeen.entries
        .where((e) => e.value.isBefore(staleCutoff))
        .map((e) => e.key)
        .toList();

    if (staleEpcs.isEmpty) return;

    // Clean up EMA and tracking state for stale tags
    for (final epc in staleEpcs) {
      _tagLastSeen.remove(epc);
      _tagSmoothedRssi.remove(epc);
      _tagReadCount.remove(epc);
    }

    // Clear focus refs if they point to stale tags
    if (staleEpcs.contains(_currentFocusEpc)) {
      _previousFocusEpc = _currentFocusEpc;
      _currentFocusEpc = null;
    }
    if (staleEpcs.contains(_previousFocusEpc)) {
      _previousFocusEpc = null;
    }

    // Filter detected tags to only include non-stale ones
    final currentTags = state.detectedTags
        .where((tag) => _tagLastSeen.containsKey(tag.epcHex))
        .toList();

    if (currentTags.length != state.detectedTags.length) {
      // Re-evaluate focus if it was cleared
      if (_currentFocusEpc == null) {
        _updateFocusTracking(currentTags);
      }

      state = state.copyWith(
        detectedTags: currentTags,
        focusTagEpc: _currentFocusEpc,
        previousFocusTagEpc: _previousFocusEpc,
      );
    }
  }

  /// Write to the strongest unwritten tag
  Future<bool> writeToActiveTag() async {
    final activeTag = state.writeCandidateTag;
    if (activeTag == null) {
      state = state.copyWith(lastError: 'No unwritten tag detected');
      return false;
    }

    if (state.roll == null) {
      state = state.copyWith(lastError: 'No roll selected');
      return false;
    }

    final activityLog = _ref.read(activityLogProvider.notifier);

    AppLogger.info(
      'RollWrite: Writing to tag ${activeTag.formattedEpc} at position ${state.currentPosition}',
    );

    state = state.copyWith(
      isWriting: true,
      currentOperation: 'Generating EPC...',
      clearError: true,
      writeSuccess: false,
    );

    // Stop polling during write
    final uhfService = _ref.read(uhfRfidServiceProvider);
    await uhfService.stopPolling();
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      // Generate new EPC
      final newEpc = RfidTag.generateEpc();
      final formattedEpc = _formatEpc(newEpc);

      AppLogger.info('RollWrite: Generated EPC: $formattedEpc');
      activityLog.info('Writing EPC $formattedEpc...', relatedEpc: newEpc);

      state = state.copyWith(currentOperation: 'Writing to tag...');

      // Write to tag — use Select to target the specific tag
      final epcBytes = _hexToBytes(newEpc);
      final targetEpcBytes = _hexToBytes(activeTag.epcHex);
      final writeResult = await uhfService.writeEpc(epcBytes, targetEpc: targetEpcBytes);

      if (!writeResult.success) {
        activityLog.error('Write failed - tag may be locked or moved');
        state = state.copyWith(
          isWriting: false,
          lastError: 'Write failed - retry or check tag',
          currentOperation: 'Scanning for tags...',
        );
        // Resume polling
        if (state.isScanning) {
          await uhfService.startPolling();
        }
        return false;
      }

      // Write successful - save to database
      state = state.copyWith(currentOperation: 'Saving to database...');

      final currentUser = await _ref.read(currentUserProvider.future);
      final tagRepo = _ref.read(rfidTagRepositoryProvider);

      await tagRepo.createAndWriteTagForRoll(
        epc: newEpc,
        createdBy: currentUser?.id,
        rollId: state.roll!.id,
        rollPosition: state.currentPosition,
      );

      // Add to known EPCs
      _knownDatabaseEpcs.add(newEpc.toUpperCase());

      // Transition focus: written tag moves to left slot
      _previousFocusEpc = activeTag.epcHex;
      _currentFocusEpc = null; // re-determined on next poll

      // Success!
      activityLog.success(
        'Tag written at position ${state.currentPosition}: $formattedEpc',
        relatedEpc: newEpc,
      );

      // Update state
      state = state.copyWith(
        isWriting: false,
        currentPosition: state.currentPosition + 1,
        currentOperation: 'Scanning for tags...',
        writeSuccess: true,
        previousFocusTagEpc: _previousFocusEpc,
        focusTagEpc: null, // re-determined on next poll
      );

      // Invalidate providers to refresh data
      _ref.invalidate(filteredRfidTagsProvider);
      _ref.invalidate(tagCountForRollProvider(state.roll!.id));
      _ref.invalidate(nextPositionForRollProvider(state.roll!.id));

      // Resume polling
      if (state.isScanning) {
        await uhfService.startPolling();
      }

      return true;
    } catch (e) {
      AppLogger.error('RollWrite: Write failed', e);
      activityLog.error('Write error: $e');

      state = state.copyWith(
        isWriting: false,
        lastError: 'Error: $e',
        currentOperation: 'Scanning for tags...',
      );

      // Resume polling
      if (state.isScanning) {
        await uhfService.startPolling();
      }

      return false;
    }
  }

  /// Mark the roll as ready to print (finish writing)
  Future<bool> finishWriting() async {
    if (state.roll == null) return false;

    await stopScanning();

    final activityLog = _ref.read(activityLogProvider.notifier);
    final rollManagement = _ref.read(rfidTagRollManagementProvider);

    try {
      await rollManagement.markReadyToPrint(state.roll!.id);
      activityLog.success('Roll marked as ready to print');

      // Update local state
      final updatedRoll = state.roll!.copyWith(
        status: RfidTagRollStatus.readyToPrint,
      );
      state = state.copyWith(roll: updatedRoll);

      return true;
    } catch (e) {
      state = state.copyWith(lastError: 'Failed to finish: $e');
      return false;
    }
  }

  /// Clear the write success state
  void clearWriteSuccess() {
    state = state.copyWith(writeSuccess: false);
  }

  /// Clear any error state
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Set RF power level (0-30 dBm)
  /// Lower power helps isolate single tags for roll writing
  Future<bool> setRfPower(int powerDbm) async {
    final uhfService = _ref.read(uhfRfidServiceProvider);
    final activityLog = _ref.read(activityLogProvider.notifier);

    if (!uhfService.isConnected) {
      state = state.copyWith(lastError: 'RFID module not connected');
      return false;
    }

    final success = await uhfService.setRfPower(powerDbm);
    if (success) {
      activityLog.info('RF power set to $powerDbm dBm');
      AppLogger.info('RollWrite: RF power set to $powerDbm dBm');
    } else {
      activityLog.error('Failed to set RF power');
      state = state.copyWith(lastError: 'Failed to set RF power');
    }
    return success;
  }

  /// Get current RF power level
  Future<int?> getRfPower() async {
    final uhfService = _ref.read(uhfRfidServiceProvider);
    if (!uhfService.isConnected) return null;
    return await uhfService.getRfPower();
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
    _staleTagTimer?.cancel();
    _staleTagTimer = null;
    _pollSubscription?.cancel();
    _pollSubscription = null;
    super.dispose();
  }
}

/// Provider for roll write state and control
final rollWriteProvider =
    StateNotifierProvider<RollWriteNotifier, RollWriteState>((ref) {
  final notifier = RollWriteNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

/// Provider for checking if roll write scanning is active
final isRollWriteScanningProvider = Provider<bool>((ref) {
  return ref.watch(rollWriteProvider).isScanning;
});

/// Provider for the active tag (strongest unwritten tag)
final activeTagProvider = Provider<DetectedTag?>((ref) {
  return ref.watch(rollWriteProvider).activeTag;
});
