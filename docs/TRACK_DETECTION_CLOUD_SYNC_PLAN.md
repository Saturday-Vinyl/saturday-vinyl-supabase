# Track Detection & Cloud-Connected Playback Sync — Architecture Plan

## Current State Analysis

### What exists today
- **Local timer only**: `startedAt` is stored in `SharedPreferences`. Each device runs its own independent countdown. There is no cloud record of the active playback session.
- **Album + side level only**: The system knows _what album_ and _which side_, but has no concept of which _track_ is currently playing.
- **One-way detection**: Hub detects a record (RFID) → Edge Function creates `user_now_playing_notifications` → app subscribes via Supabase Realtime. But the app's playback state (timer, side, manual plays) is never written back to the cloud.
- **Widgets have no track info**: The Live Activity / Dynamic Island receives album title, artist, side, and duration — but not the current track name or position.
- **No multi-device awareness**: If a user opens the app on their iPad while their iPhone is tracking a record, the iPad has no idea playback is happening.

### What works well and should be preserved
- `startedAt`-based timer design (avoids drift; widget calculates locally from timestamp)
- Realtime subscription architecture for hub events
- Track duration contribution system (crowdsourced durations)
- Live Activity / Dynamic Island integration pattern
- SharedPreferences persistence for local crash recovery

---

## Architecture Overview

### Core Concept: `playback_sessions` — The Cloud Source of Truth

We introduce a single new table `playback_sessions` that represents an **active or recently-completed listening session**. This replaces SharedPreferences as the authoritative state for "what is playing right now" and makes it accessible to all of a user's devices.

```
┌─────────────────────────────────────────────────────────────────┐
│                     playback_sessions                           │
│                                                                 │
│  id, user_id, library_album_id                                  │
│  current_side, side_started_at                                  │
│  current_track_index, current_track_position, current_track_title│
│  tracks (JSONB - snapshot of side tracks with durations)        │
│  album_title, album_artist, cover_image_url                     │
│  source (manual | hub_detected), device_id                      │
│  status (playing | stopped)                                     │
│  started_at, ended_at                                           │
│  updated_at                                                     │
│                                                                 │
│  Realtime: ENABLED                                              │
│  RLS: user can only see/modify their own sessions               │
│  Constraint: max 1 active (status='playing') session per user   │
└─────────────────────────────────────────────────────────────────┘
```

**Why one table instead of separate "session" + "events"?**
Vinyl playback is simple — play, flip side, stop. There are no pause/resume or seek operations. A single mutable row with Realtime subscriptions is the simplest path to multi-device sync. The row is updated on side-flip and track progression; all subscribers get the new state instantly.

---

## Implementation Plan

### Phase 1: Track Detection Algorithm (Pure Dart, no DB changes)

**Goal**: Given `startedAt`, `elapsedSeconds`, and a list of tracks with durations, determine which track is currently playing.

#### 1a. Create `TrackPositionCalculator` utility

**File**: `lib/utils/track_position_calculator.dart`

```dart
class TrackPosition {
  final int trackIndex;          // 0-based index into the side's track list
  final Track track;             // The Track object
  final int trackElapsedSeconds; // How far into this track we are
  final int trackTotalSeconds;   // Total duration of this track
  final bool isEstimated;        // True if any tracks lacked durations (was estimated)
}

class TrackPositionCalculator {
  /// Given elapsed seconds and a list of tracks for the current side,
  /// returns which track is likely playing.
  static TrackPosition? calculate({
    required int elapsedSeconds,
    required List<Track> sideTracks,
  });
}
```

**Algorithm**:
1. Walk through `sideTracks` in order, accumulating durations
2. When `cumulativeDuration > elapsedSeconds`, we've found the current track
3. `trackElapsedSeconds = elapsedSeconds - (cumulativeDuration - track.durationSeconds)`
4. If we run past all tracks, return the last track with overtime
5. If any track has `durationSeconds == null`, distribute unknown time proportionally based on known tracks, or mark as estimated

#### 1b. Create `currentTrackProvider` (Riverpod)

**File**: `lib/providers/current_track_provider.dart`

A provider that combines `nowPlayingProvider` state with a 1-second timer to emit the current `TrackPosition`. This is derived state — it reads the existing `startedAt` and `currentSideTracks` and calculates which track is playing right now.

```dart
final currentTrackProvider = StateNotifierProvider<CurrentTrackNotifier, TrackPosition?>(...);
```

Updates every second (same cadence as `FlipTimer`). Avoids duplicating the timer by potentially sharing with the existing flip timer logic.

#### 1c. Update UI — Now Playing Track List

Modify `NowPlayingTrackList` / `_TrackRow` to accept an optional `currentTrackIndex` and visually highlight the currently playing track with:
- A "now playing" indicator (animated equalizer bars or a pulsing dot)
- Bold text for the current track
- Elapsed time within the current track shown next to its duration

#### 1d. Update UI — Now Playing Screen

Add a "Now Playing" track card between the flip timer and the track list:
```
┌──────────────────────────────────┐
│  ♫ Now Playing                   │
│  A3 · Blue in Green             │
│  ▶ 2:14 / 5:37                  │
└──────────────────────────────────┘
```

This gives the "digital streamer" feel — the user sees exactly which track the needle is on.

---

### Phase 2: Cloud Playback Sessions (Database + Provider)

**Goal**: Persist the active playback session to Supabase so it's accessible from any device.

#### 2a. Database migration

**File**: `shared-supabase/supabase/migrations/YYYYMMDD_mobile_playback_sessions.sql`

Creates the `playback_sessions` table with:
- Core fields as described in the architecture overview
- `tracks` JSONB column: snapshot of the current side's tracks at session start (so widgets and other devices don't need to join to `albums`)
- Denormalized album metadata (title, artist, cover URL) for widget/notification use
- `status` enum: `playing` or `stopped`
- Partial unique index: `(user_id) WHERE status = 'playing'` — enforces max one active session per user
- RLS policies: users can SELECT/INSERT/UPDATE/DELETE their own sessions; service role has full access
- Realtime publication enabled
- `updated_at` auto-updates via trigger

#### 2b. `PlaybackSessionRepository`

**File**: `lib/repositories/playback_session_repository.dart`

```dart
class PlaybackSessionRepository {
  /// Start a new playback session (upserts — stops any existing session first)
  Future<PlaybackSession> startSession({...});

  /// Update the current session (side flip, track progression)
  Future<void> updateSession(String sessionId, {...});

  /// Stop the active session
  Future<void> stopSession(String sessionId);

  /// Get the user's active session (if any)
  Future<PlaybackSession?> getActiveSession(String userId);

  /// Subscribe to changes on the user's active session
  Stream<PlaybackSession?> watchActiveSession(String userId);
}
```

#### 2c. Update `NowPlayingNotifier` to sync with cloud

Modify `now_playing_provider.dart`:
- On `setNowPlaying()` / `setAutoDetected()`: create a cloud `playback_session`
- On `toggleSide()` / `setSide()`: update the cloud session with new side + reset `side_started_at`
- On `clearNowPlaying()`: stop the cloud session
- On app launch / `_restoreState()`: check cloud for an active session first, fall back to SharedPreferences
- Continue writing to SharedPreferences as a local cache for offline/fast startup

The cloud write is fire-and-forget (non-blocking). The local timer continues to be the primary driver of the UI. Cloud sync is eventual consistency — the app doesn't wait for the cloud round-trip to update the timer.

#### 2d. Track progression updates

Every time the `currentTrackProvider` detects a track change (new `trackIndex`), update the cloud session's `current_track_index`, `current_track_position`, and `current_track_title`. This happens ~once per track (every few minutes), not every second — minimal write load.

---

### Phase 3: Multi-Device Sync (Realtime Subscription)

**Goal**: When a user opens the app on a second device, it picks up the active session.

#### 3a. `PlaybackSessionSyncProvider`

**File**: `lib/providers/playback_session_sync_provider.dart`

On initialization:
1. Query `playback_sessions` for the user's active session (`status = 'playing'`)
2. If found, populate `nowPlayingProvider` with the session data (album, side, `side_started_at`)
3. Subscribe to Realtime changes on `playback_sessions` filtered by `user_id`
4. On UPDATE (side flip, track change): update local state
5. On status → `stopped`: clear local state

**Conflict resolution**: If the local device has an active session and receives a cloud update from another device:
- Cloud always wins for `startedAt` / `side` / `currentTrack` (latest `updated_at`)
- This is a "last writer wins" model, which is appropriate for vinyl (only one turntable playing at a time per user in most cases)

#### 3b. External device support

The `playback_sessions` table can be written to by any authenticated client — not just the mobile app. Future devices (e.g., a Saturday Hub with a display, a web dashboard, or a smart home integration) can:
- INSERT a new session (hub detects a record and starts a session directly)
- UPDATE `side_started_at` (hub detects a flip via accelerometer or user input)
- UPDATE `status = 'stopped'` (record removed)

The mobile app just subscribes and reacts. The `source` column tracks where the session originated.

---

### Phase 4: Widget Enrichment (Live Activity + Dynamic Island)

**Goal**: Pass current track info to the iOS widgets.

#### 4a. Update `LiveActivityService`

Add track data to the UserDefaults payload:
```dart
'currentTrackTitle': currentTrack?.track.title ?? '',
'currentTrackPosition': currentTrack?.track.position ?? '',
'currentTrackIndex': currentTrack?.trackIndex ?? -1,
'currentTrackElapsed': currentTrack?.trackElapsedSeconds ?? 0,
'currentTrackDuration': currentTrack?.trackTotalSeconds ?? 0,
'totalTracks': sideTracks.length,
```

#### 4b. Update `FlipTimerWidgetLiveActivity.swift`

Add current track display to Lock Screen and Dynamic Island:
- **Lock Screen**: Show track title under album title (e.g., "A3 · Blue in Green")
- **Dynamic Island expanded**: Replace artist in bottom region with current track
- **Dynamic Island compact**: No change (too small for track info)

#### 4c. Update `LiveActivityProvider`

The 30-second periodic update already exists. Extend it to include the current track data from `currentTrackProvider`.

---

### Phase 5: Edge Function Enhancement (Hub → Session)

**Goal**: When the hub detects a record, create/update a `playback_session` directly from the Edge Function.

#### 5a. Update `process-now-playing-event` Edge Function

**File**: `shared-supabase/supabase/functions/process-now-playing-event/index.ts`

After resolving the album from the EPC tag:
- On `placed`: Upsert a `playback_sessions` row with `status = 'playing'`, `source = 'hub_detected'`, denormalized album/track data
- On `removed`: Update the session to `status = 'stopped'`, set `ended_at`

This means the session is created in the cloud _before_ the mobile app even receives the Realtime notification. When the app subscribes, the session is already there.

---

## Data Flow Diagrams

### Manual Play (user taps album in app)
```
App (Device A)
  ├─ setNowPlaying(album)
  ├─ Write to SharedPreferences (local cache)
  ├─ INSERT playback_sessions (cloud)
  ├─ Start local timer
  ├─ Start Live Activity (widget)
  └─ currentTrackProvider begins calculating

App (Device B) — already subscribed to Realtime
  ├─ Receives playback_sessions INSERT
  ├─ Populates nowPlayingProvider
  ├─ Starts local timer from session.side_started_at
  └─ Starts Live Activity
```

### Hub Detection
```
Hub detects record (RFID)
  └─ POST to now_playing_events

Edge Function (process-now-playing-event)
  ├─ Resolve EPC → album
  ├─ UPSERT playback_sessions (status=playing, source=hub_detected)
  ├─ INSERT user_now_playing_notifications
  └─ Send push notification

App (all devices) — subscribed to Realtime
  ├─ Receives playback_sessions change
  ├─ Populates nowPlayingProvider with album + tracks
  ├─ Starts local timer from session.side_started_at
  └─ currentTrackProvider calculates current track
```

### Track Change (automatic, every few minutes)
```
currentTrackProvider detects new trackIndex
  ├─ UPDATE playback_sessions SET current_track_index, current_track_title
  ├─ Update Live Activity with new track info
  └─ Other devices receive Realtime UPDATE → update their UI
```

---

## Migration Details

### `playback_sessions` table DDL

```sql
CREATE TABLE IF NOT EXISTS playback_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  library_album_id uuid REFERENCES library_albums(id) ON DELETE SET NULL,

  -- Album metadata (denormalized for widget/notification use)
  album_title   text,
  album_artist  text,
  cover_image_url text,

  -- Playback state
  current_side  text NOT NULL DEFAULT 'A',
  side_started_at timestamptz NOT NULL DEFAULT now(),

  -- Current track (updated as playback progresses)
  current_track_index   int,
  current_track_position text,  -- e.g. "A3"
  current_track_title    text,  -- e.g. "Blue in Green"

  -- Snapshot of current side's tracks (JSONB array)
  tracks        jsonb,

  -- Session metadata
  source        text NOT NULL DEFAULT 'manual',  -- 'manual' | 'hub_detected'
  device_id     uuid REFERENCES units(id) ON DELETE SET NULL,
  status        text NOT NULL DEFAULT 'playing',  -- 'playing' | 'stopped'

  -- Timestamps
  started_at    timestamptz NOT NULL DEFAULT now(),
  ended_at      timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Only one active session per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_sessions_active_user
  ON playback_sessions (user_id) WHERE status = 'playing';

-- Fast lookup by user
CREATE INDEX IF NOT EXISTS idx_playback_sessions_user_id
  ON playback_sessions (user_id, status);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_playback_session_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER playback_sessions_updated_at
  BEFORE UPDATE ON playback_sessions
  FOR EACH ROW EXECUTE FUNCTION update_playback_session_timestamp();

-- RLS
ALTER TABLE playback_sessions ENABLE ROW LEVEL SECURITY;

-- Users can manage their own sessions
CREATE POLICY playback_sessions_select ON playback_sessions
  FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

CREATE POLICY playback_sessions_insert ON playback_sessions
  FOR INSERT WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

CREATE POLICY playback_sessions_update ON playback_sessions
  FOR UPDATE USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

CREATE POLICY playback_sessions_delete ON playback_sessions
  FOR DELETE USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

-- Service role (for Edge Functions)
CREATE POLICY playback_sessions_service ON playback_sessions
  FOR ALL USING (auth.role() = 'service_role');

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE playback_sessions;
```

---

## File Changes Summary

### New files
| File | Purpose |
|------|---------|
| `lib/utils/track_position_calculator.dart` | Pure logic: elapsed time → current track |
| `lib/providers/current_track_provider.dart` | 1-second provider emitting current TrackPosition |
| `lib/models/playback_session.dart` | Dart model for playback_sessions table |
| `lib/repositories/playback_session_repository.dart` | CRUD for playback_sessions |
| `lib/providers/playback_session_sync_provider.dart` | Realtime subscription + multi-device sync |
| `lib/widgets/now_playing/current_track_card.dart` | "Now Playing" track display card |
| `shared-supabase/supabase/migrations/YYYYMMDD_mobile_playback_sessions.sql` | DB migration |

### Modified files
| File | Changes |
|------|---------|
| `lib/providers/now_playing_provider.dart` | Add cloud session sync on play/stop/flip |
| `lib/widgets/now_playing/now_playing_track_list.dart` | Highlight current track |
| `lib/screens/now_playing/now_playing_screen.dart` | Add current track card, wire up provider |
| `lib/services/live_activity_service.dart` | Add track data to widget payload |
| `ios/FlipTimerWidget/FlipTimerWidgetLiveActivity.swift` | Display current track in widget |
| `lib/providers/live_activity_provider.dart` | Include track data in periodic updates |
| `shared-supabase/supabase/functions/process-now-playing-event/index.ts` | Create/stop playback_sessions on hub events |

---

## Implementation Order

1. **Phase 1** (Track Detection) — No backend changes, pure UI feature, can ship independently
2. **Phase 2** (Cloud Sessions) — Database migration + repository + provider wiring
3. **Phase 3** (Multi-Device Sync) — Realtime subscription, builds on Phase 2
4. **Phase 4** (Widget Enrichment) — Builds on Phase 1, independent of Phase 2/3
5. **Phase 5** (Edge Function) — Builds on Phase 2, makes hub detection create sessions directly

Phases 1 and 4 can be developed in parallel. Phase 2 is the critical path for Phases 3 and 5.

---

## Design Decisions & Trade-offs

1. **Denormalized album/track data in `playback_sessions`**: Widgets and other devices need this data without joining. A few extra bytes per session is worth avoiding cross-table queries from Edge Functions and native widgets.

2. **`tracks` JSONB snapshot**: We snapshot the current side's tracks at session start rather than referencing the canonical `albums.tracks`. This ensures consistency even if track data is updated mid-session (e.g., by a duration contribution).

3. **Partial unique index for active sessions**: Enforces at most one active session per user at the database level, preventing race conditions from multiple devices starting sessions simultaneously.

4. **Local timer remains primary**: The app doesn't poll the cloud for elapsed time. It uses `side_started_at` from the cloud session but runs the countdown locally. This ensures smooth 1-second updates without network dependency.

5. **Fire-and-forget cloud writes**: Session updates (track changes, side flips) are written to the cloud asynchronously. If the write fails (offline), the local experience is unaffected. On next successful write, the cloud catches up.

6. **Last-writer-wins for conflicts**: If two devices both try to flip the side simultaneously, the last write wins. This is acceptable because vinyl playback is inherently single-source (one turntable).
