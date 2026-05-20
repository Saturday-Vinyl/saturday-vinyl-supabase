import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/repositories/repositories.dart';

/// Provider for UserRepository.
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

/// Provider for LibraryRepository.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository();
});

/// Provider for AlbumRepository.
final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  return AlbumRepository();
});

/// Provider for CratelistRepository.
final cratelistRepositoryProvider = Provider<CratelistRepository>((ref) {
  return CratelistRepository();
});

/// Provider for PlaybackQueueRepository.
final playbackQueueRepositoryProvider =
    Provider<PlaybackQueueRepository>((ref) {
  return PlaybackQueueRepository();
});

/// Provider for TagRepository.
final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository();
});

/// Provider for DeviceRepository.
///
/// **DEPRECATED:** Use [unitRepositoryProvider] instead for the new unified schema.
@Deprecated('Use unitRepositoryProvider instead')
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  // ignore: deprecated_member_use_from_same_package
  return DeviceRepository();
});

/// Provider for UnitRepository.
///
/// This repository provides access to the unified `units` + `devices` schema.
final unitRepositoryProvider = Provider<UnitRepository>((ref) {
  return UnitRepository();
});

/// Provider for ListeningHistoryRepository.
final listeningHistoryRepositoryProvider =
    Provider<ListeningHistoryRepository>((ref) {
  return ListeningHistoryRepository();
});

/// Provider for AlbumAnalyticsRepository.
final albumAnalyticsRepositoryProvider =
    Provider<AlbumAnalyticsRepository>((ref) {
  return AlbumAnalyticsRepository();
});

/// Provider for AlbumLocationRepository.
final albumLocationRepositoryProvider =
    Provider<AlbumLocationRepository>((ref) {
  return AlbumLocationRepository();
});

/// Provider for InvitationRepository.
final invitationRepositoryProvider = Provider<InvitationRepository>((ref) {
  return InvitationRepository();
});

/// Provider for PlaybackSessionRepository.
final playbackSessionRepositoryProvider =
    Provider<PlaybackSessionRepository>((ref) {
  return PlaybackSessionRepository();
});

/// Provider for TrackDurationRepository.
final trackDurationRepositoryProvider =
    Provider<TrackDurationRepository>((ref) {
  return TrackDurationRepository();
});
