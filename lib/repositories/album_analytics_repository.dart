import 'package:saturday_consumer_app/models/album_analytics.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for fetching aggregated album analytics for the current user.
///
/// Backed by the `get_user_album_analytics` Postgres RPC, which returns the
/// full payload (totals + top lists + decade buckets + daily activity) in a
/// single round-trip and scopes itself to the authenticated user via
/// `auth.uid()` server-side.
class AlbumAnalyticsRepository extends BaseRepository {
  static const _rpcName = 'get_user_album_analytics';

  Future<AlbumAnalytics> fetchAnalytics({
    int topLimit = 5,
    int activityDays = 30,
  }) async {
    final response = await client.rpc(
      _rpcName,
      params: {
        'p_top_limit': topLimit,
        'p_activity_days': activityDays,
      },
    );

    if (response is! Map) {
      throw StateError(
        'Unexpected response from $_rpcName: ${response.runtimeType}',
      );
    }

    return AlbumAnalytics.fromJson(response.cast<String, dynamic>());
  }
}
