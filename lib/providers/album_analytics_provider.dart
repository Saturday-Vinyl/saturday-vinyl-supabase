import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/album_analytics.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// Fetches the current user's album analytics from the
/// `get_user_album_analytics` RPC.
///
/// Re-fetches whenever the signed-in user changes. Returns null if no user is
/// signed in (the screen handles the unauthenticated case).
final albumAnalyticsProvider = FutureProvider<AlbumAnalytics?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final repo = ref.watch(albumAnalyticsRepositoryProvider);
  return repo.fetchAnalytics();
});
