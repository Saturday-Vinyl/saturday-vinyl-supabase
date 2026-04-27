import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/cratelist.dart';
import 'package:saturday_consumer_app/models/cratelist_item.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';

/// All cratelists the current user is a member of, most-recently-updated first.
final userCratelistsProvider = FutureProvider<List<Cratelist>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final repo = ref.watch(cratelistRepositoryProvider);
  return repo.getUserCratelists(userId);
});

/// All cratelists with first-4-covers + count for tile rendering.
final cratelistPreviewsProvider =
    FutureProvider<List<CratelistPreview>>((ref) async {
  final cratelists = await ref.watch(userCratelistsProvider.future);
  final repo = ref.watch(cratelistRepositoryProvider);

  return Future.wait(cratelists.map(repo.getCratelistPreview));
});

/// A single cratelist by id.
final cratelistByIdProvider =
    FutureProvider.family<Cratelist?, String>((ref, cratelistId) async {
  final repo = ref.watch(cratelistRepositoryProvider);
  return repo.getCratelist(cratelistId);
});

/// Items in a cratelist, ordered by stored position, with joined library_album
/// + album metadata.
final cratelistItemsProvider =
    FutureProvider.family<List<CratelistItem>, String>(
        (ref, cratelistId) async {
  final repo = ref.watch(cratelistRepositoryProvider);
  return repo.getCratelistItems(cratelistId);
});
