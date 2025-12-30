import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/env_config.dart';
import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/services/claude_vision_service.dart';
import 'package:saturday_consumer_app/services/discogs_service.dart';

/// Provider for the Discogs service.
final discogsServiceProvider = Provider<DiscogsService>((ref) {
  return DiscogsService(
    personalAccessToken: EnvConfig.discogsPersonalAccessToken,
  );
});

/// Provider for the Claude Vision service (album cover recognition).
final claudeVisionServiceProvider = Provider<ClaudeVisionService?>((ref) {
  final apiKey = EnvConfig.anthropicApiKey;
  if (apiKey == null || apiKey.isEmpty) {
    return null;
  }
  return ClaudeVisionService(apiKey: apiKey);
});

/// State for the add album flow.
class AddAlbumState {
  final bool isLoading;
  final String? error;
  final List<DiscogsSearchResult> searchResults;
  final Album? selectedAlbum;
  final bool isAdding;
  final LibraryAlbum? addedAlbum;

  const AddAlbumState({
    this.isLoading = false,
    this.error,
    this.searchResults = const [],
    this.selectedAlbum,
    this.isAdding = false,
    this.addedAlbum,
  });

  AddAlbumState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    List<DiscogsSearchResult>? searchResults,
    Album? selectedAlbum,
    bool clearSelectedAlbum = false,
    bool? isAdding,
    LibraryAlbum? addedAlbum,
    bool clearAddedAlbum = false,
  }) {
    return AddAlbumState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchResults: searchResults ?? this.searchResults,
      selectedAlbum:
          clearSelectedAlbum ? null : (selectedAlbum ?? this.selectedAlbum),
      isAdding: isAdding ?? this.isAdding,
      addedAlbum: clearAddedAlbum ? null : (addedAlbum ?? this.addedAlbum),
    );
  }
}

/// StateNotifier for managing the add album flow.
class AddAlbumNotifier extends StateNotifier<AddAlbumState> {
  AddAlbumNotifier(this._ref) : super(const AddAlbumState());

  final Ref _ref;

  DiscogsService get _discogs => _ref.read(discogsServiceProvider);

  /// Search Discogs for albums.
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: [], clearError: true);
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final results = await _discogs.search(query);
      state = state.copyWith(
        isLoading: false,
        searchResults: results,
      );
    } on DiscogsRateLimitException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
    } on DiscogsApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to search: $e',
      );
    }
  }

  /// Search by barcode.
  Future<void> searchByBarcode(String barcode) async {
    if (barcode.trim().isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final results = await _discogs.searchByBarcode(barcode);
      state = state.copyWith(
        isLoading: false,
        searchResults: results,
      );

      // If exactly one result, auto-select it
      if (results.length == 1) {
        await selectFromSearchResult(results.first);
      }
    } on DiscogsRateLimitException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
    } on DiscogsApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to search by barcode: $e',
      );
    }
  }

  /// Search by album cover photo using Claude Vision.
  ///
  /// Returns the identified album info for display, or null if identification failed.
  Future<AlbumIdentificationResult?> searchByAlbumCover(
      Uint8List imageBytes) async {
    final visionService = _ref.read(claudeVisionServiceProvider);
    if (visionService == null) {
      state = state.copyWith(
        error: 'Album cover recognition is not configured. '
            'Please add ANTHROPIC_API_KEY to your .env file.',
      );
      return null;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Step 1: Identify the album using Claude Vision
      final identification = await visionService.identifyAlbumCover(imageBytes);

      if (!identification.isSuccessful) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not identify the album. Please try again or search manually.',
        );
        return identification;
      }

      // Step 2: Search Discogs with the identified artist/album
      final results = await _discogs.search(identification.searchQuery);
      state = state.copyWith(
        isLoading: false,
        searchResults: results,
      );

      // If exactly one result, auto-select it
      if (results.length == 1) {
        await selectFromSearchResult(results.first);
      }

      return identification;
    } on ClaudeVisionException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
      return null;
    } on DiscogsRateLimitException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
      return null;
    } on DiscogsApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to identify album: $e',
      );
      return null;
    }
  }

  /// Select an album from search results to view details.
  Future<void> selectFromSearchResult(DiscogsSearchResult result) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final album = await _discogs.getRelease(result.id);
      if (album != null) {
        state = state.copyWith(
          isLoading: false,
          selectedAlbum: album,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to load album details',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load album details: $e',
      );
    }
  }

  /// Clear the selected album.
  void clearSelection() {
    state = state.copyWith(clearSelectedAlbum: true);
  }

  /// Add the selected album to the current library.
  Future<bool> addToLibrary() async {
    final album = state.selectedAlbum;
    if (album == null) return false;

    final libraryId = _ref.read(currentLibraryIdProvider);
    final userId = _ref.read(currentUserIdProvider);

    if (libraryId == null || userId == null) {
      state = state.copyWith(error: 'No library selected or not signed in');
      return false;
    }

    state = state.copyWith(isAdding: true, clearError: true);

    try {
      final albumRepo = _ref.read(albumRepositoryProvider);

      // Check if album already exists (by Discogs ID)
      Album? existingAlbum;
      if (album.discogsId != null) {
        existingAlbum = await albumRepo.getAlbumByDiscogsId(album.discogsId!);
      }

      // Create canonical album if it doesn't exist
      final canonicalAlbum = existingAlbum ?? await albumRepo.createAlbum(album);

      // Add to library
      final libraryAlbum = await albumRepo.addAlbumToLibrary(
        libraryId,
        canonicalAlbum.id,
        userId,
      );

      state = state.copyWith(
        isAdding: false,
        addedAlbum: libraryAlbum,
      );

      return true;
    } catch (e) {
      state = state.copyWith(
        isAdding: false,
        error: 'Failed to add album: $e',
      );
      return false;
    }
  }

  /// Reset the entire flow state.
  void reset() {
    state = const AddAlbumState();
  }

  /// Clear just the error.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Provider for the add album flow state.
final addAlbumProvider =
    StateNotifierProvider<AddAlbumNotifier, AddAlbumState>((ref) {
  return AddAlbumNotifier(ref);
});

/// Provider for Discogs search results.
final discogsSearchResultsProvider = Provider<List<DiscogsSearchResult>>((ref) {
  return ref.watch(addAlbumProvider).searchResults;
});

/// Provider for the currently selected album (before adding).
final selectedAlbumProvider = Provider<Album?>((ref) {
  return ref.watch(addAlbumProvider).selectedAlbum;
});

/// Provider for whether the add flow is loading.
final isAddingAlbumProvider = Provider<bool>((ref) {
  final state = ref.watch(addAlbumProvider);
  return state.isLoading || state.isAdding;
});
