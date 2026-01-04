import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/providers/activity_log_provider.dart';
import 'package:saturday_app/providers/niimbot_provider.dart';
import 'package:saturday_app/providers/rfid_tag_roll_provider.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// State for roll print mode
class RollPrintState {
  /// The roll being printed
  final RfidTagRoll? roll;

  /// Tags to print, in roll order
  final List<RfidTag> tags;

  /// Whether printing is active
  final bool isPrinting;

  /// Whether printing is paused
  final bool isPaused;

  /// Current position being printed (1-indexed)
  final int currentPosition;

  /// Total number of tags to print
  final int totalTags;

  /// Number of tags successfully printed
  final int printedCount;

  /// Number of failed print attempts
  final int failedCount;

  /// Current operation description
  final String? currentOperation;

  /// Last error encountered
  final String? lastError;

  /// Whether the print job is complete
  final bool isComplete;

  const RollPrintState({
    this.roll,
    this.tags = const [],
    this.isPrinting = false,
    this.isPaused = false,
    this.currentPosition = 1,
    this.totalTags = 0,
    this.printedCount = 0,
    this.failedCount = 0,
    this.currentOperation,
    this.lastError,
    this.isComplete = false,
  });

  /// Progress percentage (0.0 - 1.0)
  double get progress {
    if (totalTags == 0) return 0.0;
    return printedCount / totalTags;
  }

  /// Get the current tag being printed
  RfidTag? get currentTag {
    if (tags.isEmpty || currentPosition < 1) return null;
    // Find tag at current position
    try {
      return tags.firstWhere(
        (t) => t.rollPosition == currentPosition,
      );
    } catch (_) {
      return null;
    }
  }

  RollPrintState copyWith({
    RfidTagRoll? roll,
    List<RfidTag>? tags,
    bool? isPrinting,
    bool? isPaused,
    int? currentPosition,
    int? totalTags,
    int? printedCount,
    int? failedCount,
    String? currentOperation,
    String? lastError,
    bool? isComplete,
    bool clearOperation = false,
    bool clearError = false,
    bool clearRoll = false,
  }) {
    return RollPrintState(
      roll: clearRoll ? null : (roll ?? this.roll),
      tags: tags ?? this.tags,
      isPrinting: isPrinting ?? this.isPrinting,
      isPaused: isPaused ?? this.isPaused,
      currentPosition: currentPosition ?? this.currentPosition,
      totalTags: totalTags ?? this.totalTags,
      printedCount: printedCount ?? this.printedCount,
      failedCount: failedCount ?? this.failedCount,
      currentOperation:
          clearOperation ? null : (currentOperation ?? this.currentOperation),
      lastError: clearError ? null : (lastError ?? this.lastError),
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

/// Notifier for managing roll print operations
class RollPrintNotifier extends StateNotifier<RollPrintState> {
  final Ref _ref;
  final QRService _qrService = QRService();

  /// Delay between prints to allow label feeding
  static const _printDelay = Duration(milliseconds: 2000);

  /// Flag to track if we should continue printing
  bool _shouldContinue = false;

  RollPrintNotifier(this._ref) : super(const RollPrintState());

  /// Initialize with a specific roll
  Future<void> initializeRoll(String rollId) async {
    AppLogger.info('RollPrint: Initializing for roll $rollId');

    // Load the roll
    final rollRepo = _ref.read(rfidTagRollRepositoryProvider);
    final roll = await rollRepo.getRollById(rollId);

    if (roll == null) {
      state = state.copyWith(lastError: 'Roll not found');
      return;
    }

    // Load tags for this roll, sorted by position
    final tags = await rollRepo.getTagsForRoll(rollId);
    tags.sort((a, b) => (a.rollPosition ?? 0).compareTo(b.rollPosition ?? 0));

    // Determine starting position
    final startPosition = roll.lastPrintedPosition + 1;

    state = RollPrintState(
      roll: roll,
      tags: tags,
      currentPosition: startPosition,
      totalTags: tags.length,
    );

    AppLogger.info(
      'RollPrint: Initialized roll ${roll.shortId}, ${tags.length} tags, starting at position $startPosition',
    );
  }

  /// Start printing from the current position
  Future<bool> startPrinting() async {
    if (state.isPrinting) {
      AppLogger.warning('RollPrint: Already printing');
      return true;
    }

    if (state.roll == null) {
      state = state.copyWith(lastError: 'No roll selected');
      return false;
    }

    if (state.tags.isEmpty) {
      state = state.copyWith(lastError: 'No tags to print');
      return false;
    }

    final printer = _ref.read(niimbotPrinterProvider);
    final activityLog = _ref.read(activityLogProvider.notifier);

    if (!printer.isConnected) {
      const error = 'Printer not connected';
      state = state.copyWith(lastError: error);
      activityLog.error(error);
      return false;
    }

    AppLogger.info('RollPrint: Starting print job at position ${state.currentPosition}');
    activityLog.info('Starting batch print...');

    _shouldContinue = true;
    state = state.copyWith(
      isPrinting: true,
      isPaused: false,
      currentOperation: 'Preparing to print...',
      clearError: true,
      isComplete: false,
    );

    // Update roll status to printing
    final rollManagement = _ref.read(rfidTagRollManagementProvider);
    await rollManagement.updateRollStatus(
      state.roll!.id,
      RfidTagRollStatus.printing,
    );

    // Start the print loop
    _runPrintLoop();

    return true;
  }

  /// Pause printing
  void pausePrinting() {
    if (!state.isPrinting || state.isPaused) return;

    AppLogger.info('RollPrint: Pausing print');
    _shouldContinue = false;
    state = state.copyWith(
      isPaused: true,
      currentOperation: 'Paused',
    );
  }

  /// Resume printing after pause
  void resumePrinting() {
    if (!state.isPrinting || !state.isPaused) return;

    AppLogger.info('RollPrint: Resuming print');
    _shouldContinue = true;
    state = state.copyWith(
      isPaused: false,
      currentOperation: 'Resuming...',
    );

    _runPrintLoop();
  }

  /// Stop printing completely
  Future<void> stopPrinting() async {
    if (!state.isPrinting) return;

    AppLogger.info('RollPrint: Stopping print');
    _shouldContinue = false;

    final activityLog = _ref.read(activityLogProvider.notifier);
    activityLog.info(
      'Print stopped: ${state.printedCount}/${state.totalTags} labels printed',
    );

    state = state.copyWith(
      isPrinting: false,
      isPaused: false,
      clearOperation: true,
    );
  }

  /// Start printing from a specific position
  Future<bool> startFromPosition(int position) async {
    if (position < 1 || position > state.totalTags) {
      state = state.copyWith(lastError: 'Invalid position');
      return false;
    }

    state = state.copyWith(currentPosition: position);
    return startPrinting();
  }

  /// Main print loop
  Future<void> _runPrintLoop() async {
    final printer = _ref.read(niimbotPrinterProvider);
    final activityLog = _ref.read(activityLogProvider.notifier);
    final rollRepo = _ref.read(rfidTagRollRepositoryProvider);

    while (_shouldContinue && state.currentPosition <= state.totalTags) {
      final currentTag = state.currentTag;

      if (currentTag == null) {
        // No tag at this position, skip
        AppLogger.warning(
          'RollPrint: No tag at position ${state.currentPosition}, skipping',
        );
        state = state.copyWith(currentPosition: state.currentPosition + 1);
        continue;
      }

      // Generate QR code for this tag
      state = state.copyWith(
        currentOperation:
            'Generating QR code (${state.currentPosition}/${state.totalTags})...',
      );

      Uint8List qrData;
      try {
        qrData = await _qrService.generateTagQRCode(
          currentTag.epcIdentifier,
          size: 240, // Match printer width
          embedLogo: true,
        );
      } catch (e) {
        AppLogger.error('RollPrint: Failed to generate QR code', e);
        state = state.copyWith(
          lastError: 'Failed to generate QR code: $e',
          failedCount: state.failedCount + 1,
          currentPosition: state.currentPosition + 1,
        );
        continue;
      }

      // Print the QR code
      state = state.copyWith(
        currentOperation:
            'Printing label ${state.currentPosition}/${state.totalTags}...',
      );

      final printSuccess = await printer.printImage(
        qrData,
        density: 3,
        labelWidthPx: 240,
      );

      if (printSuccess) {
        // Update print progress in database
        await rollRepo.updateLastPrintedPosition(
          state.roll!.id,
          state.currentPosition,
        );

        activityLog.success(
          'Printed label ${state.currentPosition}: ${_formatEpc(currentTag.epcIdentifier)}',
          relatedEpc: currentTag.epcIdentifier,
        );

        state = state.copyWith(
          printedCount: state.printedCount + 1,
          currentPosition: state.currentPosition + 1,
        );
      } else {
        AppLogger.error(
          'RollPrint: Failed to print label ${state.currentPosition}',
        );
        activityLog.error('Failed to print label ${state.currentPosition}');

        state = state.copyWith(
          lastError: 'Print failed at position ${state.currentPosition}',
          failedCount: state.failedCount + 1,
        );

        // Pause on error to allow user to retry or skip
        pausePrinting();
        return;
      }

      // Wait before next print
      if (_shouldContinue && state.currentPosition <= state.totalTags) {
        await Future.delayed(_printDelay);
      }
    }

    // Check if we completed all prints
    if (_shouldContinue && state.currentPosition > state.totalTags) {
      _completePrintJob();
    }
  }

  /// Complete the print job
  Future<void> _completePrintJob() async {
    AppLogger.info('RollPrint: Print job complete');

    final activityLog = _ref.read(activityLogProvider.notifier);
    final rollManagement = _ref.read(rfidTagRollManagementProvider);

    // Mark roll as complete
    await rollManagement.updateRollStatus(
      state.roll!.id,
      RfidTagRollStatus.completed,
    );

    activityLog.success(
      'Batch print complete: ${state.printedCount} labels printed',
    );

    state = state.copyWith(
      isPrinting: false,
      isComplete: true,
      currentOperation: 'Complete!',
    );
  }

  /// Retry printing the current tag
  Future<void> retryCurrentTag() async {
    if (!state.isPaused) return;

    state = state.copyWith(clearError: true);
    resumePrinting();
  }

  /// Skip the current tag and continue
  void skipCurrentTag() {
    if (!state.isPaused) return;

    state = state.copyWith(
      currentPosition: state.currentPosition + 1,
      clearError: true,
    );
    resumePrinting();
  }

  /// Clear any error state
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Format EPC for display
  String _formatEpc(String hex) {
    final upper = hex.toUpperCase();
    if (upper.length != 24) return upper;
    return '${upper.substring(0, 4)}-${upper.substring(4, 8)}-${upper.substring(8, 12)}-${upper.substring(12, 16)}-${upper.substring(16, 20)}-${upper.substring(20, 24)}';
  }

  @override
  void dispose() {
    _shouldContinue = false;
    super.dispose();
  }
}

/// Provider for roll print state and control
final rollPrintProvider =
    StateNotifierProvider<RollPrintNotifier, RollPrintState>((ref) {
  final notifier = RollPrintNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

/// Provider for checking if roll printing is active
final isRollPrintingProvider = Provider<bool>((ref) {
  return ref.watch(rollPrintProvider).isPrinting;
});

/// Provider for print progress percentage
final rollPrintProgressProvider = Provider<double>((ref) {
  return ref.watch(rollPrintProvider).progress;
});
