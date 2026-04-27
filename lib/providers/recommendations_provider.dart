import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/album_recommendation.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/services/recommendation_service.dart';
import 'package:saturday_consumer_app/services/server_recommendation_service.dart';

/// Provider for the RecommendationService singleton.
final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  return RecommendationService();
});

/// Provider for album recommendations based on currently playing album.
///
/// Returns an empty list if nothing is playing or no recommendations found.
/// Automatically invalidates when the now playing album changes.
final recommendationsProvider =
    FutureProvider<List<LibraryAlbum>>((ref) async {
  // Watch the now playing state
  final nowPlayingState = ref.watch(nowPlayingProvider);
  final currentAlbum = nowPlayingState.currentAlbum;

  // If nothing is playing, return empty
  if (currentAlbum == null) return [];

  // Get the current library ID
  final libraryId = ref.watch(currentLibraryIdProvider);
  if (libraryId == null) return [];

  // Get all albums in the current library
  final libraryAlbumsAsync = ref.watch(libraryAlbumsProvider);

  return libraryAlbumsAsync.when(
    data: (albums) {
      // Get recommendations
      final service = ref.read(recommendationServiceProvider);
      return service.getRecommendations(
        currentAlbum,
        albums,
        limit: 10,
      );
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Provider for recommendations that includes recently played as fallback.
///
/// If the recommendation engine doesn't find enough matches, it supplements
/// with recently played albums.
final upNextProvider = FutureProvider<List<LibraryAlbum>>((ref) async {
  final recommendations = await ref.watch(recommendationsProvider.future);

  // If we have enough recommendations, use them
  if (recommendations.length >= 5) {
    return recommendations;
  }

  // Otherwise, supplement with recently played
  final recentlyPlayed = await ref.watch(recentlyPlayedProvider.future);
  final nowPlayingState = ref.watch(nowPlayingProvider);
  final currentAlbumId = nowPlayingState.currentAlbum?.id;

  // Combine recommendations with recently played, avoiding duplicates
  final combined = <LibraryAlbum>[...recommendations];
  final seenIds = recommendations.map((a) => a.id).toSet();

  for (final album in recentlyPlayed) {
    if (!seenIds.contains(album.id) && album.id != currentAlbumId) {
      combined.add(album);
      seenIds.add(album.id);
      if (combined.length >= 10) break;
    }
  }

  return combined;
});

/// Provider for the server-side recommendation edge function. Used for the
/// "your queue is empty" carousel, where we want server-scored results
/// (affinity + staleness + last-known location) rather than the local
/// affinity-only logic above.
final serverRecommendationServiceProvider =
    Provider<ServerRecommendationService>((ref) {
  return ServerRecommendationService();
});

/// Server-scored recommendations seeded by the currently-playing album, if
/// any. Returns up to [limit] suggestions. Surfaced in the empty-queue
/// state on the Now Playing screen.
final serverRecommendationsProvider =
    FutureProvider.family<List<AlbumRecommendation>, int>(
        (ref, limit) async {
  final nowPlaying = ref.watch(nowPlayingProvider);
  final service = ref.watch(serverRecommendationServiceProvider);
  return service.getRecommendations(
    currentLibraryAlbumId: nowPlaying.currentAlbum?.id,
    limit: limit,
  );
});
