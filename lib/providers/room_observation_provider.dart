import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/room_observation.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/repositories/room_observation_repository.dart';

final roomObservationRepositoryProvider =
    Provider<RoomObservationRepository>((ref) {
  return RoomObservationRepository();
});

/// The single observation the listening room shows on this visit.
///
/// Resolves to `null` when no category meets its threshold — the room
/// then shows nothing, which is the constitutionally-preferred outcome.
/// Refetches when the signed-in listener changes, not on a timer; one
/// observation per visit is the design.
final roomObservationProvider =
    FutureProvider<RoomObservation?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final repo = ref.watch(roomObservationRepositoryProvider);
  return repo.fetchOne();
});
