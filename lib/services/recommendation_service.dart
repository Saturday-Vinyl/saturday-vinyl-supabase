import 'package:saturday_consumer_app/models/library_album.dart';

/// Service for generating album recommendations.
///
/// Uses genre/style matching to suggest albums that are similar
/// to the currently playing album.
class RecommendationService {
  /// Gets recommendations for the current album.
  ///
  /// Scores albums by:
  /// - Genre match (3 points each)
  /// - Style match (2 points each)
  /// - Same artist (5 points)
  /// - Same label (1 point)
  /// - Same decade (1 point)
  ///
  /// Returns albums sorted by score, excluding the current album.
  List<LibraryAlbum> getRecommendations(
    LibraryAlbum current,
    List<LibraryAlbum> libraryAlbums, {
    int limit = 10,
  }) {
    final currentAlbum = current.album;
    if (currentAlbum == null) return [];

    // Calculate scores for each album
    final scored = <_ScoredAlbum>[];

    for (final libraryAlbum in libraryAlbums) {
      // Skip the current album
      if (libraryAlbum.id == current.id) continue;

      final album = libraryAlbum.album;
      if (album == null) continue;

      int score = 0;

      // Genre matching (3 points each)
      for (final genre in currentAlbum.genres) {
        if (album.genres.contains(genre)) {
          score += 3;
        }
      }

      // Style matching (2 points each)
      for (final style in currentAlbum.styles) {
        if (album.styles.contains(style)) {
          score += 2;
        }
      }

      // Same artist (5 points)
      if (_normalizeArtist(album.artist) ==
          _normalizeArtist(currentAlbum.artist)) {
        score += 5;
      }

      // Same label (1 point)
      if (album.label != null &&
          currentAlbum.label != null &&
          album.label!.toLowerCase() == currentAlbum.label!.toLowerCase()) {
        score += 1;
      }

      // Same decade (1 point)
      if (album.year != null && currentAlbum.year != null) {
        final currentDecade = (currentAlbum.year! ~/ 10) * 10;
        final albumDecade = (album.year! ~/ 10) * 10;
        if (currentDecade == albumDecade) {
          score += 1;
        }
      }

      // Only include if there's some match
      if (score > 0) {
        scored.add(_ScoredAlbum(libraryAlbum, score));
      }
    }

    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Return top results
    return scored.take(limit).map((s) => s.album).toList();
  }

  /// Normalizes artist name for comparison.
  String _normalizeArtist(String artist) {
    // Remove "The " prefix and lowercase
    var normalized = artist.toLowerCase().trim();
    if (normalized.startsWith('the ')) {
      normalized = normalized.substring(4);
    }
    return normalized;
  }
}

/// Internal class for sorting albums by score.
class _ScoredAlbum {
  final LibraryAlbum album;
  final int score;

  _ScoredAlbum(this.album, this.score);
}
