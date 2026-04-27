import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/playback_queue_item.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/services/supabase_service.dart';

/// State for the user's persisted playback queue.
class PlaybackQueueState {
  final List<PlaybackQueueItem> items;
  final bool isLoading;
  final String? error;

  const PlaybackQueueState({
    this.items = const [],
    this.isLoading = true,
    this.error,
  });

  PlaybackQueueState copyWith({
    List<PlaybackQueueItem>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PlaybackQueueState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// StateNotifier that holds the user's playback queue and keeps it in
/// sync via Supabase realtime. Mutations are delegated to the
/// [PlaybackQueueRepository] and refresh through the realtime feed.
class PlaybackQueueNotifier extends StateNotifier<PlaybackQueueState> {
  PlaybackQueueNotifier(this._ref) : super(const PlaybackQueueState()) {
    _initialize();
  }

  final Ref _ref;
  StreamSubscription<dynamic>? _subscription;
  String? _lastUserId;

  void _initialize() {
    _ref.listen<String?>(currentUserIdProvider, (previous, next) {
      if (previous != next) _bind(next);
    }, fireImmediately: true);
  }

  Future<void> _bind(String? userId) async {
    await _subscription?.cancel();
    _subscription = null;
    _lastUserId = userId;

    if (userId == null) {
      state = const PlaybackQueueState(isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _refresh(userId);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return;
    }

    // Realtime: stream() doesn't support joins, so any change just triggers
    // a refetch with the embed query.
    _subscription = SupabaseService.instance.client
        .from('playback_queue')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen(
      (_) {
        if (_lastUserId != null && _lastUserId == userId) {
          _refresh(userId);
        }
      },
      onError: (Object error) {
        state = state.copyWith(error: error.toString());
      },
    );
  }

  Future<void> _refresh(String userId) async {
    final repo = _ref.read(playbackQueueRepositoryProvider);
    final items = await repo.getQueue(userId);
    if (mounted && _lastUserId == userId) {
      state = state.copyWith(items: items, isLoading: false, clearError: true);
    }
  }

  /// Append a single album to the end of the queue.
  Future<void> addAlbum(String libraryAlbumId) async {
    final userId = _lastUserId;
    if (userId == null) return;
    await _ref
        .read(playbackQueueRepositoryProvider)
        .addItem(userId: userId, libraryAlbumId: libraryAlbumId);
  }

  /// Append a list of albums to the end of the queue, in order.
  Future<void> addAlbums(List<String> libraryAlbumIds) async {
    final userId = _lastUserId;
    if (userId == null || libraryAlbumIds.isEmpty) return;
    await _ref.read(playbackQueueRepositoryProvider).addItems(
          userId: userId,
          libraryAlbumIds: libraryAlbumIds,
        );
  }

  /// Clear the queue and append the given albums in order. Used by Play /
  /// Shuffle on a cratelist.
  Future<void> replaceWith(List<String> libraryAlbumIds) async {
    final userId = _lastUserId;
    if (userId == null) return;
    await _ref.read(playbackQueueRepositoryProvider).replaceQueue(
          userId: userId,
          libraryAlbumIds: libraryAlbumIds,
        );
  }

  Future<void> removeItem(String itemId) async {
    await _ref.read(playbackQueueRepositoryProvider).removeItem(itemId);
  }

  Future<void> clear() async {
    final userId = _lastUserId;
    if (userId == null) return;
    await _ref.read(playbackQueueRepositoryProvider).clearQueue(userId);
  }

  Future<void> reorder(List<String> orderedItemIds) async {
    await _ref
        .read(playbackQueueRepositoryProvider)
        .reorder(orderedItemIds: orderedItemIds);
  }

  /// Optimistically update the local order ahead of the server confirming.
  void setLocalOrder(List<PlaybackQueueItem> items) {
    state = state.copyWith(items: items);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final playbackQueueProvider =
    StateNotifierProvider<PlaybackQueueNotifier, PlaybackQueueState>((ref) {
  return PlaybackQueueNotifier(ref);
});

/// Convenience: the next 1..n items at the head of the queue, used by the
/// Now Playing "Up next" widget.
final upcomingQueueItemsProvider =
    Provider.family<List<PlaybackQueueItem>, int>((ref, count) {
  final items = ref.watch(playbackQueueProvider).items;
  return items.take(count).toList();
});

/// Returns true when the queue is empty (and not still loading).
final isQueueEmptyProvider = Provider<bool>((ref) {
  final state = ref.watch(playbackQueueProvider);
  return !state.isLoading && state.items.isEmpty;
});

/// Auto-advance: whenever the now-playing album changes, consume the head
/// of the queue if it matches. Watching this provider in a screen wires
/// the behavior up; the provider itself returns nothing.
///
/// Per design: only the lowest-position item with the detected
/// library_album_id is removed (option B). If the same album is queued
/// again later, that next instance survives.
final queueAutoAdvanceProvider = Provider<void>((ref) {
  String? lastConsumedKey;

  ref.listen<String?>(
    nowPlayingProvider.select((s) => s.currentAlbum?.id),
    (previous, next) async {
      if (next == null) return;
      // Each unique now-playing change triggers at most one consume; reuse
      // the same key while the same album stays current.
      final key = next;
      if (lastConsumedKey == key) return;
      lastConsumedKey = key;

      final userId = ref.read(currentUserIdProvider);
      if (userId == null) return;

      final repo = ref.read(playbackQueueRepositoryProvider);
      await repo.consumeFirstMatch(
        userId: userId,
        libraryAlbumId: next,
      );
    },
    fireImmediately: true,
  );
});
