import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_details.dart';
import 'package:saturday_consumer_app/models/library_member_with_user.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// FutureProvider.family for fetching comprehensive library details.
///
/// Returns library info with album count, members, and popular albums.
final libraryDetailsProvider =
    FutureProvider.family<LibraryDetails, String>((ref, libraryId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getLibraryDetails(libraryId);
});

/// FutureProvider for the current library's details.
///
/// Returns null if no library is selected.
final currentLibraryDetailsProvider =
    FutureProvider<LibraryDetails?>((ref) async {
  final currentId = ref.watch(currentLibraryIdProvider);
  if (currentId == null) return null;

  return ref.watch(libraryDetailsProvider(currentId).future);
});

/// FutureProvider.family for library members with user info.
///
/// Fetches members along with their user profile data.
final libraryMembersWithUsersProvider =
    FutureProvider.family<List<LibraryMemberWithUser>, String>(
        (ref, libraryId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getLibraryMembersWithUsers(libraryId);
});

/// FutureProvider.family for popular albums in a library.
///
/// Returns the most played albums ordered by play count.
final popularAlbumsProvider =
    FutureProvider.family<List<PopularLibraryAlbum>, String>(
        (ref, libraryId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getPopularAlbums(libraryId, limit: 5);
});

/// FutureProvider.family for the album count in a library.
final libraryAlbumCountProvider =
    FutureProvider.family<int, String>((ref, libraryId) async {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.getLibraryAlbumCount(libraryId);
});
