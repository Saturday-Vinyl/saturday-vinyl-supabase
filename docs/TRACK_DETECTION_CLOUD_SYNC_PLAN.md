# Track Detection & Cloud-Connected Playback Sync — Architecture Plan

**Version:** 2.0
**Last Updated:** 2026-03-13

---

## Current State Analysis

### What exists today
- **Local timer only**: `startedAt` is stored in `SharedPreferences`. Each device runs its own independent countdown. There is no cloud record of the active playback session.
- **Album + side level only**: The system knows _what album_ and _which side_, but has no concept of which _track_ is currently playing.
- **One-way detection**: Hub detects a record (RFID) → Edge Function creates `user_now_playing_notifications` → app subscribes via Supabase Realtime. But the app's playback state (timer, side, manual plays) is never written back to the cloud.
- **Widgets have no track info**: The Live Activity / Dynamic Island receives album title, artist, side, and duration — but not the current track name or position.
- **No multi-device awareness**: If a user opens the app on their iPad while their iPhone is tracking a record, the iPad has no idea playback is happening.
- **Hub detection = play start**: Currently, placing a record jacket on the hub immediately triggers playback. There is no "queued" state — no opportunity to select a side or confirm before the timer starts.

### What works well and should be preserved
- `startedAt`-based timer design (avoids drift; widget calculates locally from timestamp)
- Realtime subscription architecture for hub events
- Track duration contribution system (crowdsourced durations)
- Live Activity / Dynamic Island integration pattern
- SharedPreferences persistence for local crash recovery
- `device_commands` + `broadcast_device_command` pattern for sending commands to hubs via their MAC-address channel

---

## Architecture Overview

### Core Concept: Cloud-First Playback with Event-Driven Sync

We introduce two new tables that work together:

1. **`playback_sessions`** — The current state snapshot. Represents what is happening right now (or recently happened). Any device or app can query this to immediately get caught up. This is what widgets read, what the app queries on launch, and what drives the UI.

2. **`playback_events`** — The append-only event log. Every state change is recorded as a discrete event with its source. Supabase Realtime subscriptions on this table keep all connected devices in sync in real-time. Events are the mechanism of sync; the session row is the materialized result.

### State Machine

A playback session has four possible statuses:

```
                     ┌──────────────────────────┐
                     │                          │
                     ▼                          │
┌─────────┐    ┌─────────┐    ┌─────────┐     │
│ queued  │───►│ playing │───►│ stopped │     │
└─────────┘    └─────────┘    └─────────┘     │
     │              │                          │
     │              │  side_changed            │
     │              └──────────────────────────┘
     │
     ▼
┌───────────┐
│ cancelled │
└───────────┘
```

- **`queued`**: Album identified (via RFID scan or app selection), waiting for the user to press play. Side defaults to A but can be changed. No timer running.
- **`playing`**: Timer is running. `side_started_at` is set. Track position is being calculated. All devices sync.
- **`stopped`**: Session ended normally. User tapped stop, or started a new album.
- **`cancelled`**: Queued session was dismissed without ever playing (e.g., hub detected record removal before play started).

### Constraints

- **Max 1 `playing` session per user** (partial unique index)
- **Max 1 `queued` session per user** (partial unique index)
- **Both can coexist**: An album can be playing while another is queued as "up next"
- Queuing a new album while one is already queued replaces the queued album (previous → `cancelled`)
- Starting a queued album while another is playing stops the playing album first (previous → `stopped`)

### Table Schemas

```
┌─────────────────────────────────────────────────────────────────────┐
│                       playback_sessions                             │
│                                                                     │
│  id, user_id, library_album_id                                      │
│  album_title, album_artist, cover_image_url                         │
│                                                                     │
│  status (queued | playing | stopped | cancelled)                    │
│  current_side (default 'A')                                         │
│  side_started_at (NULL when queued, set when playing)               │
│                                                                     │
│  current_track_index, current_track_position, current_track_title   │
│  tracks (JSONB - snapshot of current side's tracks with durations)  │
│  side_a_duration_seconds, side_b_duration_seconds                   │
│                                                                     │
│  queued_by_source (app | hub | web | api)                           │
│  queued_by_device_id (uuid, nullable, FK → units)                   │
│  started_by_source (app | hub | web | api, nullable)                │
│  started_by_device_id (uuid, nullable, FK → units)                  │
│                                                                     │
│  started_at, ended_at, updated_at, created_at                       │
│                                                                     │
│  Realtime: ENABLED                                                  │
│  RLS: user can only see/modify their own sessions                   │
│  Partial unique: max 1 queued + max 1 playing per user              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       playback_events                               │
│                                                                     │
│  id, session_id (FK → playback_sessions)                            │
│  user_id (FK → users, denormalized for RLS/subscription filtering)  │
│  event_type (session_queued | side_changed | playback_started |     │
│              playback_stopped | session_cancelled)                   │
│  payload (JSONB - event-specific data)                              │
│                                                                     │
│  source_type (app | hub | web | api)                                │
│  source_device_id (uuid, nullable, FK → units)                      │
│  created_at                                                         │
│                                                                     │
│  Realtime: ENABLED                                                  │
│  RLS: user can only see their own events                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Event Types

| Event | Payload | Effect on `playback_sessions` |
|-------|---------|-------------------------------|
| `session_queued` | `{library_album_id, album_title, album_artist, cover_image_url, current_side, tracks, side_a_duration_seconds, side_b_duration_seconds}` | INSERT session with `status: queued` |
| `side_changed` | `{side, tracks}` | UPDATE `current_side`, `tracks` (snapshot of new side) |
| `playback_started` | `{}` | UPDATE `status: playing`, `side_started_at: now()`, `started_at: now()` |
| `playback_stopped` | `{}` | UPDATE `status: stopped`, `ended_at: now()` |
| `session_cancelled` | `{}` | UPDATE `status: cancelled` |

Each event carries `source_type` and `source_device_id` so we always know _what_ initiated each action.

### Track Progression

**Track position is NOT an event.** It is derived state calculated deterministically from `side_started_at` + `tracks` JSONB (which includes durations). Any device with this data arrives at the same answer independently.

Track progression is handled by:
1. **Mobile apps (foregrounded)**: Calculate locally every second for UI display. When a track boundary is crossed, UPDATE `playback_sessions.current_track_index/title/position` for the benefit of widgets and non-calculating devices.
2. **Server-side cron (~30 seconds)**: For sessions where the app is backgrounded or closed, a Supabase cron job calculates the current track and updates the session row + sends ActivityKit push to update iOS Live Activities.
3. **Any capable device**: Can perform the same calculation and write the update. Since the calculation is deterministic from the same inputs, these writes are idempotent — multiple devices writing the same track index is harmless.

No leader election is needed. The cron provides a reliable fallback when no app is foregrounded.

---

## Device Roles & Communication

### Low-Power Devices (ESP32 Hubs)

Hubs are **event publishers AND lightweight subscribers**. They do not perform track calculations.

**Publishing (fire-and-forget HTTP):**
```
Hub RFID scan → HTTP POST to edge function → playback_events INSERT
Hub play button → HTTP POST to edge function → playback_events INSERT
Hub flip button → HTTP POST to edge function → playback_events INSERT
```

The edge function is the **event gateway** — it receives simple HTTP calls from low-power devices, validates them, and translates them into `playback_events` + `playback_sessions` updates.

**Subscribing (existing Realtime WebSocket):**

Hubs already maintain a WebSocket connection for device commands on their MAC-address channel (`device:<mac>`). To deliver playback state to hubs, we use the existing `device_commands` / `broadcast_device_command` pattern:

When a playback event occurs, a database trigger (or the edge function) sends a `pg_notify` broadcast to the device channels of all units owned by the session's user. The hub receives playback state on its existing channel — no additional subscription needed.

The hub uses this data to:
- Show LEDs indicating the selected/playing side
- Run a local countdown timer for remaining duration (from `side_started_at` + side duration)

**Hub → User resolution:** The hub knows its `unit_id` (serial number stored in NVS). The edge function resolves `unit → consumer_user_id` to find the owning user and their other devices.

### Mobile Apps (iOS / Android)

Apps are **both publishers and subscribers**. They subscribe to `playback_events` via Supabase Realtime (filtered by `user_id` via RLS) and can publish events directly by INSERTing into `playback_events` or calling edge functions.

### Future Devices (Web App, Hub with Display, Smart Home)

Any authenticated client can INSERT into `playback_events`. The event model is device-agnostic — the `source_type` field distinguishes the origin.

---

## Push vs Realtime Strategy

### When to use each mechanism

| Mechanism | Works when | Latency | Use for |
|-----------|-----------|---------|---------|
| **Supabase Realtime** (WebSocket) | App is in foreground, connected | Sub-second | All event sync between devices while app is open |
| **FCM/APNs Push** | App is backgrounded, terminated, or force-closed | 1-5 seconds | Alerting the user, waking the app |
| **ActivityKit Push** (iOS) | Live Activity is active on lock screen | 1-5 seconds | Updating Live Activity when app is backgrounded |
| **Query `playback_sessions`** | Any time | ~200ms | Catch-up on app launch or reconnection |

### Event-specific delivery

| Event | Realtime | FCM Push | ActivityKit Push |
|-------|----------|----------|-----------------|
| `session_queued` | Auto (INSERT triggers Realtime) | Yes — alert user on backgrounded devices | No (no Live Activity yet) |
| `side_changed` | Auto | No | Yes (if playing, update widget) |
| `playback_started` | Auto | No | Yes (start/update Live Activity) |
| `playback_stopped` | Auto | Yes — notify backgrounded devices | Yes (end Live Activity) |
| `session_cancelled` | Auto | No | No |
| Track progression (session row UPDATE) | Auto | No | Yes (update track name on widget) |

### Mobile app behavior by state

| App state | Sync mechanism | What happens |
|-----------|---------------|--------------|
| **Foreground** | Realtime WebSocket | Events arrive instantly. App updates UI + Live Activity directly. App writes track progression to session row. |
| **Background** | ActivityKit Push | Live Activity updated by server-sent pushes. Realtime may disconnect after ~30s (iOS kills it). |
| **Terminated** | FCM Push | System notification shown (e.g., "Kind of Blue detected"). User taps → app launches. |
| **App launch** | Query `playback_sessions` | Read current state immediately. Then subscribe to Realtime for ongoing sync. SharedPreferences used for instant UI while cloud query completes. |

---

## Data Flow Diagrams

### Hub Detection → Queue → Play

```
Hub detects record (RFID scan)
  └─ POST to edge function with EPC + unit_id

Edge Function (event gateway)
  ├─ Resolve EPC → album metadata + tracks
  ├─ Resolve unit → user
  ├─ INSERT playback_events (session_queued, source=hub)
  ├─ UPSERT playback_sessions (status=queued, current_side=A, tracks=side A snapshot)
  ├─ Send FCM push ("Kind of Blue detected — tap to play")
  └─ Broadcast to user's hub device channels (album info for LED display)

All subscribed apps (Realtime)
  ├─ Receive playback_events INSERT (session_queued)
  ├─ Show queued UI: album art, side selector, play button
  └─ "Up Next" card if another album is currently playing

Hub (receives broadcast on existing device channel)
  └─ Show side indicator LEDs (default Side A)

User taps Play in app (or hub play button → edge function)
  ├─ If another album is playing → INSERT playback_events (playback_stopped) for that session
  ├─ INSERT playback_events (playback_started, source=app)
  ├─ UPDATE playback_sessions (status=playing, side_started_at=now())
  └─ Start Live Activity

All subscribed apps + hubs (Realtime / broadcast)
  ├─ Receive playback_started event
  ├─ Start local timer from side_started_at
  └─ Hub begins LED countdown
```

### Manual Play (user selects album in app)

```
App (Device A)
  ├─ User taps album → INSERT playback_events (session_queued, source=app)
  ├─ UPSERT playback_sessions (status=queued)
  ├─ Show queued UI with side selector
  │
  ├─ User confirms side, taps Play
  ├─ INSERT playback_events (playback_started, source=app)
  ├─ UPDATE playback_sessions (status=playing, side_started_at=now())
  ├─ Write to SharedPreferences (local cache)
  ├─ Start local timer
  ├─ Start Live Activity
  └─ Track position calculation begins

App (Device B) — subscribed to Realtime
  ├─ Receives session_queued → shows queued UI
  ├─ Receives playback_started → starts local timer from side_started_at
  └─ Starts Live Activity

Hub — receives broadcast on device channel
  └─ Shows side LEDs + starts countdown
```

### Side Change (before or during play)

```
User taps Side B in app (or hub flip button → edge function)
  ├─ INSERT playback_events (side_changed, source=app, payload={side: 'B', tracks: [side B tracks]})
  ├─ UPDATE playback_sessions (current_side=B, tracks=side B snapshot)
  ├─ If status=playing: reset side_started_at=now(), reset current_track_index=0
  └─ If status=queued: just update the selected side

All subscribed devices
  ├─ Receive side_changed event
  ├─ Update side display
  ├─ If playing: restart local timer with new side duration
  └─ Hub: update side indicator LEDs
```

### Hub Record Removal

```
Hub detects record removed (RFID)
  └─ POST to edge function with EPC + unit_id + event_type=removed

Edge Function
  ├─ Find the user's current sessions
  ├─ If a queued session matches this album:
  │   ├─ INSERT playback_events (session_cancelled, source=hub)
  │   └─ UPDATE playback_sessions (status=cancelled)
  ├─ If a playing session matches this album:
  │   └─ NO EFFECT (user may be looking at the jacket while listening)
  └─ Update album_locations (removed_at)
```

### Track Progression (automatic)

```
App (foregrounded) — every 1 second
  ├─ Calculate track position from side_started_at + tracks JSONB
  ├─ Update UI with current track highlight
  ├─ On track boundary crossed:
  │   ├─ UPDATE playback_sessions (current_track_index, current_track_title, current_track_position)
  │   └─ Update Live Activity with new track name

Server cron (~30 seconds) — for backgrounded/closed apps
  ├─ Query all sessions WHERE status='playing'
  ├─ Calculate current track from side_started_at + tracks
  ├─ If track changed since last update:
  │   ├─ UPDATE playback_sessions row
  │   └─ Send ActivityKit push to update Live Activity on lock screen
```

---

## Network Resilience

Moving to cloud-first introduces network dependency. Here's how we mitigate:

### 1. Optimistic local state + async cloud sync
The app updates its local UI immediately on user action. Cloud writes happen asynchronously. If a write fails (offline), the local experience is unaffected. Failed events are queued and retried on reconnection.

### 2. SharedPreferences as local cache
On every state change, the app writes to SharedPreferences AND publishes to the cloud. On app launch:
1. Read SharedPreferences → show UI instantly (offline-safe)
2. Query `playback_sessions` for cloud state
3. If cloud state is newer → update local state
4. Subscribe to `playback_events` for ongoing sync

The user sees their session immediately, even offline. Cloud reconciliation happens in the background.

### 3. Timer never depends on network
The timer runs locally from `side_started_at` (a timestamp). Once the app has that timestamp — from local cache or cloud — it calculates elapsed time independently. No network needed for the core countdown experience.

### 4. Graceful degradation
| Scenario | Behavior |
|----------|----------|
| Manual play while offline | Works fully (local only), syncs when reconnected |
| Hub detection while app offline | Push notification alerts user, app queries cloud on next launch |
| Multi-device sync interrupted | Each device continues with last-known state, re-syncs on reconnect |
| Cloud write fails | Local experience unaffected, event queued for retry |

### 5. Supabase Realtime reconnection
Supabase's Realtime client handles reconnection automatically. On reconnect, the app re-queries `playback_sessions` to catch up on missed events, then resubscribes for ongoing sync.

---

## Relationship to Existing Tables

### `user_now_playing_notifications` — Retained for push notification context

The existing `user_now_playing_notifications` table continues to serve its current purpose: providing pre-enriched data for push notifications and maintaining backward compatibility during the transition.

Once `playback_events` is fully deployed, the Realtime subscription on `user_now_playing_notifications` can be removed from the app — the app will subscribe to `playback_events` instead. The `user_now_playing_notifications` table may still be used by the edge function as a push notification trigger, or it can be retired in favor of sending pushes directly from the playback event handler.

### `now_playing_events` — Retained as hub input

The `now_playing_events` table remains the ingestion point for raw RFID events from hubs. The existing database trigger calls the `process-now-playing-event` edge function. The edge function will be updated to write `playback_events` + `playback_sessions` in addition to (or instead of) `user_now_playing_notifications`.

### `listening_history` — Updated trigger point

Currently, `listening_history` is recorded when `setNowPlaying()` or `setAutoDetected()` is called. In the new architecture, it should be recorded when a `playback_started` event occurs (transition from `queued` → `playing`), not when the album is first queued.

---

## Migration Details

### `playback_sessions` table DDL

```sql
CREATE TABLE IF NOT EXISTS playback_sessions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  library_album_id    uuid REFERENCES library_albums(id) ON DELETE SET NULL,

  -- Album metadata (denormalized for widgets/notifications/hubs)
  album_title         text,
  album_artist        text,
  cover_image_url     text,

  -- Playback state
  status              text NOT NULL DEFAULT 'queued',
  current_side        text NOT NULL DEFAULT 'A',
  side_started_at     timestamptz,  -- NULL when queued, set when playing

  -- Current track (derived, updated periodically by app or cron)
  current_track_index    int,
  current_track_position text,   -- e.g. "A3"
  current_track_title    text,   -- e.g. "Blue in Green"

  -- Track data snapshot (JSONB array of current side's tracks)
  tracks              jsonb,
  side_a_duration_seconds int,
  side_b_duration_seconds int,

  -- Source tracking
  queued_by_source    text NOT NULL DEFAULT 'app',     -- app | hub | web | api
  queued_by_device_id uuid REFERENCES units(id) ON DELETE SET NULL,
  started_by_source   text,                             -- app | hub | web | api
  started_by_device_id uuid REFERENCES units(id) ON DELETE SET NULL,

  -- Timestamps
  started_at          timestamptz,  -- when playback_started (not when queued)
  ended_at            timestamptz,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  created_at          timestamptz NOT NULL DEFAULT now(),

  -- Constraints
  CONSTRAINT valid_status CHECK (status IN ('queued', 'playing', 'stopped', 'cancelled')),
  CONSTRAINT valid_side CHECK (current_side IN ('A', 'B', 'C', 'D')),
  CONSTRAINT valid_queued_source CHECK (queued_by_source IN ('app', 'hub', 'web', 'api')),
  CONSTRAINT valid_started_source CHECK (started_by_source IS NULL OR started_by_source IN ('app', 'hub', 'web', 'api'))
);

-- Max 1 playing session per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_sessions_active_playing
  ON playback_sessions (user_id) WHERE status = 'playing';

-- Max 1 queued session per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_sessions_active_queued
  ON playback_sessions (user_id) WHERE status = 'queued';

-- Fast lookup by user + status
CREATE INDEX IF NOT EXISTS idx_playback_sessions_user_status
  ON playback_sessions (user_id, status);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_playback_session_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS playback_sessions_updated_at ON playback_sessions;
CREATE TRIGGER playback_sessions_updated_at
  BEFORE UPDATE ON playback_sessions
  FOR EACH ROW EXECUTE FUNCTION update_playback_session_timestamp();

-- RLS
ALTER TABLE playback_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "playback_sessions_select" ON playback_sessions;
CREATE POLICY "playback_sessions_select" ON playback_sessions
  FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_insert" ON playback_sessions;
CREATE POLICY "playback_sessions_insert" ON playback_sessions
  FOR INSERT WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_update" ON playback_sessions;
CREATE POLICY "playback_sessions_update" ON playback_sessions
  FOR UPDATE USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_delete" ON playback_sessions;
CREATE POLICY "playback_sessions_delete" ON playback_sessions
  FOR DELETE USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_service" ON playback_sessions;
CREATE POLICY "playback_sessions_service" ON playback_sessions
  FOR ALL USING (auth.role() = 'service_role');

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE playback_sessions;
```

### `playback_events` table DDL

```sql
CREATE TABLE IF NOT EXISTS playback_events (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id        uuid NOT NULL REFERENCES playback_sessions(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  event_type        text NOT NULL,
  payload           jsonb DEFAULT '{}',

  source_type       text NOT NULL DEFAULT 'app',
  source_device_id  uuid REFERENCES units(id) ON DELETE SET NULL,

  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Constraints
  CONSTRAINT valid_event_type CHECK (event_type IN (
    'session_queued', 'side_changed', 'playback_started',
    'playback_stopped', 'session_cancelled'
  )),
  CONSTRAINT valid_source_type CHECK (source_type IN ('app', 'hub', 'web', 'api'))
);

-- Query events by session
CREATE INDEX IF NOT EXISTS idx_playback_events_session
  ON playback_events (session_id, created_at);

-- Subscribe to events by user (for Realtime filtering)
CREATE INDEX IF NOT EXISTS idx_playback_events_user
  ON playback_events (user_id, created_at);

-- RLS
ALTER TABLE playback_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "playback_events_select" ON playback_events;
CREATE POLICY "playback_events_select" ON playback_events
  FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_events_insert" ON playback_events;
CREATE POLICY "playback_events_insert" ON playback_events
  FOR INSERT WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_events_service" ON playback_events;
CREATE POLICY "playback_events_service" ON playback_events
  FOR ALL USING (auth.role() = 'service_role');

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE playback_events;
```

### Trigger: Broadcast playback events to user's hubs

```sql
-- When a playback event is inserted, broadcast to all hub device channels
-- owned by the session's user, using the same pg_notify pattern as device_commands.
CREATE OR REPLACE FUNCTION broadcast_playback_event_to_hubs()
RETURNS TRIGGER AS $$
DECLARE
  device_record RECORD;
  channel_name TEXT;
BEGIN
  -- Find all devices belonging to units owned by this user
  FOR device_record IN
    SELECT d.mac_address
    FROM devices d
    JOIN units u ON d.unit_id = u.id
    WHERE u.consumer_user_id = NEW.user_id
      AND u.is_online = true
  LOOP
    channel_name := 'device:' || REPLACE(device_record.mac_address, ':', '-');

    PERFORM pg_notify(
      'realtime:broadcast',
      json_build_object(
        'topic', channel_name,
        'event', 'broadcast',
        'payload', json_build_object(
          'event', 'playback_event',
          'payload', json_build_object(
            'event_type', NEW.event_type,
            'session_id', NEW.session_id,
            'payload', NEW.payload,
            'source_type', NEW.source_type,
            'created_at', NEW.created_at
          )
        )
      )::text
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_playback_event_broadcast ON playback_events;
CREATE TRIGGER on_playback_event_broadcast
  AFTER INSERT ON playback_events
  FOR EACH ROW EXECUTE FUNCTION broadcast_playback_event_to_hubs();
```

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
│  Now Playing                     │
│  A3 · Blue in Green             │
│  2:14 / 5:37                    │
└──────────────────────────────────┘
```

---

### Phase 2: Cloud Playback Sessions (Database + Event System)

**Goal**: Persist the active playback session to Supabase with event-driven sync.

#### 2a. Database migration

**File**: `shared-supabase/supabase/migrations/YYYYMMDD_mobile_playback_sessions.sql`

Creates `playback_sessions` and `playback_events` tables with all indexes, constraints, RLS policies, Realtime publication, and the hub broadcast trigger as specified in the Migration Details section.

#### 2b. `PlaybackSession` and `PlaybackEvent` models

**Files**: `lib/models/playback_session.dart`, `lib/models/playback_event.dart`

Dart models with JSON serialization for both tables.

#### 2c. `PlaybackSessionRepository`

**File**: `lib/repositories/playback_session_repository.dart`

```dart
class PlaybackSessionRepository {
  /// Queue an album for playback (creates session + session_queued event)
  Future<PlaybackSession> queueAlbum({
    required String userId,
    required LibraryAlbum album,
    required String sourceType,   // app | hub | web | api
    String? sourceDeviceId,
  });

  /// Start playback on a queued session (playback_started event)
  Future<void> startPlayback({
    required String sessionId,
    required String sourceType,
    String? sourceDeviceId,
  });

  /// Change the selected side (side_changed event)
  Future<void> changeSide({
    required String sessionId,
    required String side,
    required List<Track> sideTracks,
    required String sourceType,
    String? sourceDeviceId,
  });

  /// Stop playback (playback_stopped event)
  Future<void> stopPlayback({
    required String sessionId,
    required String sourceType,
    String? sourceDeviceId,
  });

  /// Cancel a queued session (session_cancelled event)
  Future<void> cancelSession({
    required String sessionId,
    required String sourceType,
    String? sourceDeviceId,
  });

  /// Update track progression (session row update only, not an event)
  Future<void> updateTrackPosition({
    required String sessionId,
    required int trackIndex,
    required String trackPosition,
    required String trackTitle,
  });

  /// Get the user's active sessions (queued and/or playing)
  Future<List<PlaybackSession>> getActiveSessions(String userId);

  /// Subscribe to playback events for a user
  Stream<PlaybackEvent> watchEvents(String userId);
}
```

#### 2d. Update `NowPlayingNotifier` to use cloud sessions

Modify `now_playing_provider.dart`:
- Replace `setNowPlaying()` → calls `queueAlbum()` then optionally `startPlayback()` (or shows queued UI)
- Replace `setAutoDetected()` → handled by incoming `session_queued` event from Realtime
- `toggleSide()` / `setSide()` → calls `changeSide()` on the repository
- `clearNowPlaying()` → calls `stopPlayback()`
- `_restoreState()` → check cloud for active sessions first, fall back to SharedPreferences
- Continue writing to SharedPreferences as local cache

#### 2e. Now Playing Screen — Queued State

Add a new UI state between empty and playing:

```
Now Playing Screen states:
  1. Empty — nothing queued, nothing playing → show empty state with CTAs
  2. Queued — album detected/selected → show album art, side selector, Play button
  3. Playing — timer running → show flip timer, track list with highlighting
  4. Playing + Queued — split view: current album playing + "Up Next" card for queued album
```

---

### Phase 3: Multi-Device Sync (Realtime Subscription)

**Goal**: When a user opens the app on a second device, it picks up the active session. All devices stay in sync.

#### 3a. `PlaybackSyncProvider`

**File**: `lib/providers/playback_sync_provider.dart`

On initialization:
1. Query `playback_sessions` for the user's active sessions (`status IN ('queued', 'playing')`)
2. If found, populate `nowPlayingProvider` with the session data
3. Subscribe to `playback_events` via Realtime (filtered by `user_id`)
4. On each event, update local state accordingly:
   - `session_queued` → show queued UI (or "Up Next" if already playing)
   - `side_changed` → update side, restart timer if playing
   - `playback_started` → start local timer from `side_started_at`
   - `playback_stopped` → clear now playing UI
   - `session_cancelled` → remove queued album

**Conflict resolution**: Cloud always wins. If local state disagrees with an incoming event, the event takes precedence. This is appropriate because there's only one turntable — the cloud represents ground truth.

#### 3b. Transition from `realtimeNowPlayingProvider`

The existing `realtimeNowPlayingProvider` (which subscribes to `user_now_playing_notifications`) is replaced by `PlaybackSyncProvider`. The transition can be gradual:
1. Deploy Phase 2 (cloud sessions) with the edge function writing to both `user_now_playing_notifications` AND `playback_events`
2. Deploy Phase 3 (sync provider) — app subscribes to `playback_events` instead
3. Remove `user_now_playing_notifications` subscription from app
4. Eventually retire `user_now_playing_notifications` table (or keep for audit)

---

### Phase 4: Widget Enrichment (Live Activity + Dynamic Island)

**Goal**: Pass current track info to the iOS widgets and keep them updated when app is backgrounded.

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

#### 4c. Server-side track progression cron

**File**: `shared-supabase/supabase/functions/update-track-progression/index.ts`

A Supabase cron function (~30 second interval) that:
1. Queries all `playback_sessions WHERE status = 'playing'`
2. For each, calculates current track from `side_started_at` + `tracks` JSONB
3. If track changed → UPDATE session row
4. Sends ActivityKit push to update Live Activity on the user's iOS devices

This ensures Live Activities stay current even when the app is backgrounded or terminated.

#### 4d. Update `LiveActivityProvider`

The 30-second periodic update already exists for when the app is foregrounded. Extend it to include current track data from `currentTrackProvider`. When backgrounded, the server cron takes over via ActivityKit push.

---

### Phase 5: Edge Function Enhancement (Hub → Event Gateway)

**Goal**: Update the edge function to write playback events and sessions, replacing the notification-only approach.

#### 5a. Update `process-now-playing-event` Edge Function

**File**: `shared-supabase/supabase/functions/process-now-playing-event/index.ts`

After resolving the album from the EPC tag:

**On `placed`:**
1. Check if user has a queued session for this album → if yes, no-op (already queued)
2. If user has a different queued session → cancel it (→ `session_cancelled` event)
3. INSERT `playback_events` (`session_queued`, `source=hub`)
4. UPSERT `playback_sessions` (`status=queued`, `current_side=A`, album metadata, track snapshot)
5. Send FCM push notification
6. The hub broadcast trigger fires automatically on the `playback_events` INSERT

**On `removed`:**
1. If user has a queued session matching this album → cancel it (→ `session_cancelled` event)
2. If user has a playing session matching this album → **no effect** (user may be looking at jacket)
3. Update `album_locations` (existing behavior)

#### 5b. New edge function: `handle-hub-playback-action`

**File**: `shared-supabase/supabase/functions/handle-hub-playback-action/index.ts`

A new endpoint for hub button presses (play, flip, stop). Receives:
```json
{
  "unit_id": "SV-HUB-000001",
  "action": "play" | "flip" | "stop"
}
```

- **play**: Find user's queued session → INSERT `playback_started` event → UPDATE session
- **flip**: Find user's playing session → INSERT `side_changed` event → UPDATE session
- **stop**: Find user's playing session → INSERT `playback_stopped` event → UPDATE session

---

## Implementation Order

```
Phase 1 (Track Detection)          Phase 4 (Widget Enrichment)
  Pure Dart, no DB changes           Builds on Phase 1
  Can ship independently             4a-4b: can parallel with Phase 1
                                     4c-4d: needs Phase 2 for cron
       │                                    │
       ▼                                    ▼
Phase 2 (Cloud Sessions)  ◄────────────────┘
  Database migration
  Repository + event system
  NowPlayingNotifier refactor
  Queued state UI
       │
       ├──────────────────────┐
       ▼                      ▼
Phase 3 (Multi-Device Sync)  Phase 5 (Edge Function)
  Realtime subscription       Hub → event gateway
  Replace notification flow   New hub action endpoint
```

**Recommended sequence:**
1. Phase 1 — ship track detection as a standalone UI improvement
2. Phase 2 — the critical foundation (DB + events + provider refactor)
3. Phase 3 + Phase 5 in parallel — both build on Phase 2 independently
4. Phase 4 — widget enrichment, can start after Phase 1 for UI parts, needs Phase 2 for server cron

---

## File Changes Summary

### New files
| File | Purpose |
|------|---------|
| `lib/utils/track_position_calculator.dart` | Pure logic: elapsed time → current track |
| `lib/providers/current_track_provider.dart` | 1-second provider emitting current TrackPosition |
| `lib/models/playback_session.dart` | Dart model for playback_sessions table |
| `lib/models/playback_event.dart` | Dart model for playback_events table |
| `lib/repositories/playback_session_repository.dart` | CRUD + event publishing for playback |
| `lib/providers/playback_sync_provider.dart` | Realtime subscription + multi-device sync |
| `lib/widgets/now_playing/current_track_card.dart` | "Now Playing" track display card |
| `lib/widgets/now_playing/queued_album_card.dart` | "Up Next" queued album display |
| `shared-supabase/supabase/migrations/YYYYMMDD_mobile_playback_sessions.sql` | DB migration |
| `shared-supabase/supabase/functions/update-track-progression/index.ts` | Cron: track calc + ActivityKit push |
| `shared-supabase/supabase/functions/handle-hub-playback-action/index.ts` | Hub button actions endpoint |

### Modified files
| File | Changes |
|------|---------|
| `lib/providers/now_playing_provider.dart` | Refactor to use cloud sessions, add queued state |
| `lib/widgets/now_playing/now_playing_track_list.dart` | Highlight current track |
| `lib/screens/now_playing/now_playing_screen.dart` | Add queued state UI, current track card, "Up Next" |
| `lib/services/live_activity_service.dart` | Add track data to widget payload |
| `ios/FlipTimerWidget/FlipTimerWidgetLiveActivity.swift` | Display current track in widget |
| `lib/providers/live_activity_provider.dart` | Include track data in periodic updates |
| `shared-supabase/supabase/functions/process-now-playing-event/index.ts` | Write playback_events + playback_sessions |

### Eventually removed
| File | Reason |
|------|--------|
| `lib/providers/realtime_now_playing_provider.dart` | Replaced by `playback_sync_provider.dart` |

---

## Design Decisions & Trade-offs

1. **Two tables (sessions + events) instead of one mutable row**: The original plan used a single `playback_sessions` row. With the addition of queued state, multi-source tracking, and the need for real-time event sync to multiple device types, an append-only event log provides better auditability, clearer sync semantics, and per-action source tracking.

2. **Denormalized album/track data in `playback_sessions`**: Widgets, hubs, and other devices need this data without joining. A few extra bytes per session avoids cross-table queries from edge functions and native widgets.

3. **`tracks` JSONB snapshot**: We snapshot the current side's tracks at session start rather than referencing the canonical `albums.tracks`. This ensures consistency even if track data is updated mid-session (e.g., by a duration contribution).

4. **Partial unique indexes for queued + playing**: Enforces at most one queued and one playing session per user at the database level, preventing race conditions from multiple devices acting simultaneously.

5. **Track progression is derived, not evented**: Track position is deterministically calculable from `side_started_at` + track durations. Making it an event would create unnecessary write load (every few minutes per session) and introduce ordering concerns. Instead, it's a convenience UPDATE on the session row, handled by the foregrounded app or a server cron.

6. **Hub removal cancels queued but doesn't stop playing**: Removing a record from the hub likely means the user is looking at the jacket, not that they want to stop listening. Only queued (never-played) sessions are cancelled on removal.

7. **Local timer remains primary**: The app doesn't poll the cloud for elapsed time. It uses `side_started_at` from the cloud session but runs the countdown locally. This ensures smooth 1-second updates without network dependency.

8. **Fire-and-forget cloud writes with local cache**: Session updates are written asynchronously. SharedPreferences provides instant local recovery. The cloud catches up when connectivity allows.

9. **Hub receives events via existing device channel**: Rather than adding a new Realtime subscription to the ESP32, we broadcast playback events through the existing `device:<mac>` channel using the same `pg_notify` pattern as `device_commands`. Zero additional memory cost on the hub.

10. **Last-writer-wins for concurrent writes**: If two devices both change the side simultaneously, the last write wins. Acceptable because vinyl playback is inherently single-source (one turntable).

---

## Open / Future Considerations

- **Queue depth**: Currently max 1 queued album. A future enhancement could support a playlist/queue of multiple albums.
- **Audio fingerprinting**: A future hub with audio input could authoritatively detect track changes, publishing `track_changed` events with higher confidence than elapsed-time calculation.
- **Listening history enrichment**: With track-level data, we could record which tracks were actually listened to, not just which album was played.
- **ActivityKit push tokens**: Need to investigate the exact mechanism for registering and managing ActivityKit push tokens for server-side Live Activity updates.
