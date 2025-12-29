import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/tag.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/services/qr_scanner_service.dart';

/// Provider for the QR scanner service.
final qrScannerServiceProvider = Provider<QrScannerService>((ref) {
  return QrScannerService();
});

/// Provider for tags associated with a specific library album.
final tagsForAlbumProvider =
    FutureProvider.family<List<Tag>, String>((ref, libraryAlbumId) async {
  final tagRepo = ref.watch(tagRepositoryProvider);
  return tagRepo.getTagsForLibraryAlbum(libraryAlbumId);
});

/// Provider for a tag by its EPC.
final tagByEpcProvider =
    FutureProvider.family<Tag?, String>((ref, epc) async {
  final tagRepo = ref.watch(tagRepositoryProvider);
  return tagRepo.getTagByEpc(epc);
});

/// State for the tag association flow.
class TagAssociationState {
  final bool isLoading;
  final String? error;
  final String? scannedEpc;
  final Tag? existingTag;
  final bool isAssociating;
  final bool isComplete;

  const TagAssociationState({
    this.isLoading = false,
    this.error,
    this.scannedEpc,
    this.existingTag,
    this.isAssociating = false,
    this.isComplete = false,
  });

  TagAssociationState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? scannedEpc,
    bool clearScannedEpc = false,
    Tag? existingTag,
    bool clearExistingTag = false,
    bool? isAssociating,
    bool? isComplete,
  }) {
    return TagAssociationState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      scannedEpc: clearScannedEpc ? null : (scannedEpc ?? this.scannedEpc),
      existingTag:
          clearExistingTag ? null : (existingTag ?? this.existingTag),
      isAssociating: isAssociating ?? this.isAssociating,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

/// StateNotifier for managing tag association flow.
class TagAssociationNotifier extends StateNotifier<TagAssociationState> {
  TagAssociationNotifier(this._ref) : super(const TagAssociationState());

  final Ref _ref;

  /// Process a scanned QR code result.
  Future<void> processQrCode(String content) async {
    state = state.copyWith(isLoading: true, clearError: true);

    final qrService = _ref.read(qrScannerServiceProvider);
    final result = qrService.parseQrCode(content);

    switch (result) {
      case SaturdayTagResult(:final epc):
        await _checkExistingTag(epc);
      case NonSaturdayQrResult():
        state = state.copyWith(
          isLoading: false,
          error: 'This is not a Saturday tag',
        );
      case InvalidQrResult(:final message):
        state = state.copyWith(
          isLoading: false,
          error: message,
        );
    }
  }

  /// Check if the EPC is already associated with an album.
  Future<void> _checkExistingTag(String epc) async {
    try {
      final tagRepo = _ref.read(tagRepositoryProvider);
      final existingTag = await tagRepo.getTagByEpc(epc);

      if (existingTag != null && existingTag.status == TagStatus.active) {
        state = state.copyWith(
          isLoading: false,
          scannedEpc: epc,
          existingTag: existingTag,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          scannedEpc: epc,
          clearExistingTag: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to check tag: $e',
      );
    }
  }

  /// Associate the scanned tag with a library album.
  Future<bool> associateTag(String libraryAlbumId) async {
    final epc = state.scannedEpc;
    if (epc == null) {
      state = state.copyWith(error: 'No tag scanned');
      return false;
    }

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }

    state = state.copyWith(isAssociating: true, clearError: true);

    try {
      final tagRepo = _ref.read(tagRepositoryProvider);

      // If there's an existing tag, disassociate it first
      if (state.existingTag != null) {
        await tagRepo.disassociateTag(state.existingTag!.id);
      }

      // Associate the tag with the new album
      await tagRepo.associateTag(epc, libraryAlbumId, userId);

      // Invalidate the tags provider for this album
      _ref.invalidate(tagsForAlbumProvider(libraryAlbumId));

      state = state.copyWith(
        isAssociating: false,
        isComplete: true,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        isAssociating: false,
        error: 'Failed to associate tag: $e',
      );
      return false;
    }
  }

  /// Reset the state for a new scan.
  void reset() {
    state = const TagAssociationState();
  }

  /// Clear just the error.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Provider for the tag association flow state.
final tagAssociationProvider =
    StateNotifierProvider<TagAssociationNotifier, TagAssociationState>((ref) {
  return TagAssociationNotifier(ref);
});

/// Provider for whether a library album has any associated tags.
final albumHasTagsProvider =
    FutureProvider.family<bool, String>((ref, libraryAlbumId) async {
  final tags = await ref.watch(tagsForAlbumProvider(libraryAlbumId).future);
  return tags.isNotEmpty;
});
