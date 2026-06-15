import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/services/discogs_service.dart';

/// Full artist details from Discogs (bio, image, canonical name).
final discogsArtistProvider =
    FutureProvider.family.autoDispose<DiscogsArtist?, int>(
  (ref, artistId) async {
    final discogs = ref.watch(discogsServiceProvider);
    return discogs.getArtist(artistId);
  },
);

/// Albums in the current library credited to a given Discogs artist ID.
final libraryAlbumsByArtistProvider =
    FutureProvider.family.autoDispose<List<LibraryAlbum>, int>(
  (ref, artistId) async {
    final libraryId = ref.watch(currentLibraryIdProvider);
    if (libraryId == null) return const [];
    final albumRepo = ref.watch(albumRepositoryProvider);
    return albumRepo.getLibraryAlbumsByArtistId(libraryId, artistId);
  },
);

/// Paginated state for an artist's "More on Discogs" discography.
class ArtistReleasesState {
  final List<DiscogsArtistRelease> releases;
  final int currentPage;
  final int totalPages;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final String? error;

  const ArtistReleasesState({
    this.releases = const [],
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoadingInitial = false,
    this.isLoadingMore = false,
    this.error,
  });

  bool get hasMore => currentPage < totalPages;

  ArtistReleasesState copyWith({
    List<DiscogsArtistRelease>? releases,
    int? currentPage,
    int? totalPages,
    bool? isLoadingInitial,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return ArtistReleasesState(
      releases: releases ?? this.releases,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ArtistReleasesNotifier extends StateNotifier<ArtistReleasesState> {
  ArtistReleasesNotifier(this._discogs, this._artistId)
      : super(const ArtistReleasesState(isLoadingInitial: true)) {
    _loadFirstPage();
  }

  final DiscogsService _discogs;
  final int _artistId;

  Future<void> _loadFirstPage() async {
    try {
      final page = await _discogs.getArtistReleases(_artistId, page: 1);
      state = ArtistReleasesState(
        releases: page.releases,
        currentPage: page.page,
        totalPages: page.totalPages,
      );
    } catch (e) {
      state = ArtistReleasesState(error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true, clearError: true);

    try {
      final nextPage = state.currentPage + 1;
      final page =
          await _discogs.getArtistReleases(_artistId, page: nextPage);
      state = state.copyWith(
        releases: [...state.releases, ...page.releases],
        currentPage: page.page,
        totalPages: page.totalPages,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<void> retry() async {
    state = const ArtistReleasesState(isLoadingInitial: true);
    await _loadFirstPage();
  }
}

/// Paginated provider for an artist's discography on Discogs.
final discogsArtistReleasesProvider = StateNotifierProvider.family
    .autoDispose<ArtistReleasesNotifier, ArtistReleasesState, int>(
  (ref, artistId) {
    final discogs = ref.watch(discogsServiceProvider);
    return ArtistReleasesNotifier(discogs, artistId);
  },
);
