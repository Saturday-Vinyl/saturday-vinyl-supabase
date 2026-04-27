import 'package:saturday_consumer_app/models/album_recommendation.dart';
import 'package:saturday_consumer_app/services/supabase_service.dart';

/// Wraps the `recommend-albums` Supabase edge function.
///
/// Returns server-scored album recommendations from the user's library,
/// optionally taking the currently-playing album into account for affinity
/// scoring (genre, style, artist). The function also enriches results
/// with last-known crate location.
class ServerRecommendationService {
  Future<List<AlbumRecommendation>> getRecommendations({
    String? currentLibraryAlbumId,
    int limit = 5,
  }) async {
    final response = await SupabaseService.instance.client.functions.invoke(
      'recommend-albums',
      body: {
        if (currentLibraryAlbumId != null)
          'current_album_id': currentLibraryAlbumId,
        'limit': limit,
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) return [];

    final list = data['recommendations'] as List<dynamic>?;
    if (list == null) return [];

    return list
        .whereType<Map<String, dynamic>>()
        .map(AlbumRecommendation.fromJson)
        .toList();
  }
}
