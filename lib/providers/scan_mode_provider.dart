import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/tag_poll_result.dart';
import 'package:saturday_app/providers/activity_log_provider.dart';
import 'package:saturday_app/providers/rfid_settings_provider.dart';
import 'package:saturday_app/providers/rfid_tag_provider.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// State for scan mode
class ScanModeState {
  /// Whether scanning is currently active
  final bool isScanning;

  /// EPCs of Saturday tags found that exist in database
  final Set<String> foundEpcs;

  /// EPCs of Saturday tags found that do NOT exist in database
  final Set<String> unknownEpcs;

  /// EPCs of non-Saturday tags detected (for informational purposes)
  final Set<String> nonSaturdayEpcs;

  /// Last error encountered during scanning
  final String? lastError;

  const ScanModeState({
    this.isScanning = false,
    this.foundEpcs = const {},
    this.unknownEpcs = const {},
    this.nonSaturdayEpcs = const {},
    this.lastError,
  });

  /// Total number of Saturday tags found (known + unknown)
  int get saturdayTagCount => foundEpcs.length + unknownEpcs.length;

  /// Total number of all tags detected
  int get totalTagCount =>
      foundEpcs.length + unknownEpcs.length + nonSaturdayEpcs.length;

  ScanModeState copyWith({
    bool? isScanning,
    Set<String>? foundEpcs,
    Set<String>? unknownEpcs,
    Set<String>? nonSaturdayEpcs,
    String? lastError,
    bool clearError = false,
  }) {
    return ScanModeState(
      isScanning: isScanning ?? this.isScanning,
      foundEpcs: foundEpcs ?? this.foundEpcs,
      unknownEpcs: unknownEpcs ?? this.unknownEpcs,
      nonSaturdayEpcs: nonSaturdayEpcs ?? this.nonSaturdayEpcs,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  String toString() =>
      'ScanModeState(scanning: $isScanning, found: ${foundEpcs.length}, unknown: ${unknownEpcs.length}, nonSaturday: ${nonSaturdayEpcs.length})';
}

/// Notifier for managing scan mode state
class ScanModeNotifier extends StateNotifier<ScanModeState> {
  final Ref _ref;
  StreamSubscription<TagPollResult>? _pollSubscription;

  ScanModeNotifier(this._ref) : super(const ScanModeState());

  /// Start scanning for tags
  Future<bool> startScanning() async {
    if (state.isScanning) {
      AppLogger.warning('ScanMode: Already scanning');
      return true;
    }

    final uhfService = _ref.read(uhfRfidServiceProvider);
    final activityLog = _ref.read(activityLogProvider.notifier);

    if (!uhfService.isConnected) {
      const error = 'RFID module not connected';
      state = state.copyWith(lastError: error);
      activityLog.error(error);
      AppLogger.warning('ScanMode: $error');
      return false;
    }

    AppLogger.info('ScanMode: Starting scan');
    activityLog.info('Starting tag scan...');

    // Clear previous results
    state = state.copyWith(
      isScanning: true,
      foundEpcs: {},
      unknownEpcs: {},
      nonSaturdayEpcs: {},
      clearError: true,
    );

    // Apply saved RF power setting before scanning
    final settings = _ref.read(currentRfidSettingsProvider);
    final powerSet = await uhfService.setRfPower(settings.rfPower);
    if (powerSet) {
      AppLogger.info('ScanMode: RF power set to ${settings.rfPower} dBm');
    } else {
      AppLogger.warning('ScanMode: Failed to set RF power, using current module setting');
    }

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

    return true;
  }

  /// Stop scanning for tags
  Future<void> stopScanning() async {
    if (!state.isScanning) {
      return;
    }

    AppLogger.info('ScanMode: Stopping scan');

    // Cancel subscription first
    await _pollSubscription?.cancel();
    _pollSubscription = null;

    // Stop polling
    final uhfService = _ref.read(uhfRfidServiceProvider);
    await uhfService.stopPolling();

    // Log summary
    final activityLog = _ref.read(activityLogProvider.notifier);
    activityLog.info(
      'Scan complete: ${state.foundEpcs.length} known, '
      '${state.unknownEpcs.length} unknown Saturday tags',
    );

    if (state.nonSaturdayEpcs.isNotEmpty) {
      activityLog.warning(
        '${state.nonSaturdayEpcs.length} non-Saturday tags ignored',
      );
    }

    state = state.copyWith(isScanning: false);
  }

  /// Handle a detected tag
  Future<void> _onTagDetected(TagPollResult result) async {
    final epcHex = result.epcHex;

    // Skip if already processed
    if (state.foundEpcs.contains(epcHex) ||
        state.unknownEpcs.contains(epcHex) ||
        state.nonSaturdayEpcs.contains(epcHex)) {
      return;
    }

    final activityLog = _ref.read(activityLogProvider.notifier);

    // Check if this is a Saturday tag
    if (!result.isSaturdayTag) {
      AppLogger.debug('ScanMode: Non-Saturday tag detected: $epcHex');
      activityLog.warning(
        'Non-Saturday tag detected: ${result.formattedEpc}',
        relatedEpc: epcHex,
      );
      state = state.copyWith(
        nonSaturdayEpcs: {...state.nonSaturdayEpcs, epcHex},
      );
      return;
    }

    // Look up in database
    try {
      final tagRepo = _ref.read(rfidTagRepositoryProvider);
      final tag = await tagRepo.getTagByEpc(epcHex);

      if (tag != null) {
        // Found in database
        AppLogger.info('ScanMode: Known tag found: ${result.formattedEpc}');
        activityLog.success(
          'Tag found: ${result.formattedEpc}',
          relatedEpc: epcHex,
        );
        state = state.copyWith(
          foundEpcs: {...state.foundEpcs, epcHex},
        );
      } else {
        // Saturday tag but not in database
        AppLogger.warning(
            'ScanMode: Unknown Saturday tag: ${result.formattedEpc}');
        activityLog.warning(
          'Unknown Saturday tag: ${result.formattedEpc}',
          relatedEpc: epcHex,
        );
        state = state.copyWith(
          unknownEpcs: {...state.unknownEpcs, epcHex},
        );
      }
    } catch (e) {
      AppLogger.error('ScanMode: Error looking up tag', e);
      // On error, still add to unknown to avoid repeated lookups
      state = state.copyWith(
        unknownEpcs: {...state.unknownEpcs, epcHex},
      );
    }
  }

  /// Clear all found tags (reset for new scan)
  void clearFoundTags() {
    state = state.copyWith(
      foundEpcs: {},
      unknownEpcs: {},
      nonSaturdayEpcs: {},
      clearError: true,
    );
  }

  /// Check if a specific EPC was found in the current scan
  bool isEpcFound(String epc) {
    final normalized = epc.toUpperCase();
    return state.foundEpcs.contains(normalized);
  }

  /// Check if a specific EPC is unknown (Saturday tag not in DB)
  bool isEpcUnknown(String epc) {
    final normalized = epc.toUpperCase();
    return state.unknownEpcs.contains(normalized);
  }

  @override
  void dispose() {
    _pollSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for scan mode state and control
final scanModeProvider =
    StateNotifierProvider<ScanModeNotifier, ScanModeState>((ref) {
  final notifier = ScanModeNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

/// Provider for checking if a specific EPC is highlighted (found in scan)
final isEpcHighlightedProvider = Provider.family<bool, String>((ref, epc) {
  final scanState = ref.watch(scanModeProvider);
  return scanState.foundEpcs.contains(epc.toUpperCase());
});

/// Provider for checking if scanning is active
final isScanningProvider = Provider<bool>((ref) {
  return ref.watch(scanModeProvider).isScanning;
});
