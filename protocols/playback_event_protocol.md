# Saturday Playback Event Protocol

**Version:** 1.0.0
**Last Updated:** 2026-05-12
**Audience:** Saturday Mobile App developers, Hub firmware engineers, Apple TV developers, Admin App developers

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [State Machine](#state-machine)
4. [Event Types](#event-types)
5. [Event Payloads](#event-payloads)
6. [Source Types](#source-types)
7. [Session Row Reference](#session-row-reference)
8. [Hub Broadcast Trigger](#hub-broadcast-trigger)
9. [Authorization (RLS)](#authorization-rls)
10. [Sync Mechanisms](#sync-mechanisms)
11. [Track Progression](#track-progression)
12. [Relationship to `listening_history`](#relationship-to-listening_history)
13. [Implementation Reference](#implementation-reference)
14. [Version History](#version-history)

---

## Overview

This document defines the **Playback Event Protocol** — the canonical model for representing what is playing across Saturday devices. Any device or service that participates in playback (consumer app, hub firmware, Apple TV, future web client) MUST publish and consume events through this protocol so that all surfaces stay in sync.

### Key Concepts

- **Two-table model:** `playback_sessions` (current state) and `playback_events` (append-only log).
- **Cloud-canonical:** Supabase is the source of truth. Any device or app catches up by reading `playback_sessions`.
- **Event-driven sync:** State changes are published as discrete events; Supabase Realtime fans them out to all connected clients.
- **Device-agnostic:** The `source_type` field distinguishes who initiated each event. New device classes participate without protocol changes.

### Design Principles

1. **Materialized result, not derived:** The session row is the answer to "what is playing?" — clients never have to replay events to know the current state.
2. **Authoritative timestamps:** `side_started_at` and `started_at` are the canonical references for elapsed time. Local timers drift; cloud timestamps don't.
3. **Single active session per user per status:** Unique indexes enforce one `queued` and one `playing` session per user at any moment.
4. **Deterministic track derivation:** Track position is computed from `side_started_at` + the `tracks` JSONB snapshot — never broadcast as a separate event.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                       playback_sessions                              │
│                                                                     │
│  Current state snapshot. One row per session. Updated in place      │
│  as the session progresses. Queryable any time.                     │
│                                                                     │
│  Realtime: ENABLED                                                  │
│  RLS: user can only see/write their own sessions                    │
└─────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ updated by handlers when events fire
                              │
┌─────────────────────────────────────────────────────────────────────┐
│                       playback_events                                │
│                                                                     │
│  Append-only log. One row per state change. Carries `source_type`   │
│  so we always know what initiated each action.                      │
│                                                                     │
│  Realtime: ENABLED                                                  │
│  RLS: user can only see/write their own events                      │
│  Trigger: fans out to user's hub device channels via pg_notify      │
└─────────────────────────────────────────────────────────────────────┘
```

Producers INSERT into `playback_events` and UPDATE `playback_sessions` (typically in the same transaction or back-to-back). Subscribers receive events via Realtime and can either read the updated session row directly or react to the event payload.

---

## State Machine

A session has four possible statuses:

```
                     ┌──────────────────────────┐
                     │                          │
                     ▼                          │
┌─────────┐    ┌─────────┐    ┌─────────┐      │
│ queued  │───►│ playing │───►│ stopped │      │
└─────────┘    └─────────┘    └─────────┘      │
     │              │                           │
     │              │  side_changed             │
     │              └───────────────────────────┘
     │
     ▼
┌───────────┐
│ cancelled │
└───────────┘
```

| Status | Meaning |
|--------|---------|
| `queued` | Album identified (RFID scan or app selection), waiting for the user to start playback. `side_started_at` is NULL. |
| `playing` | Timer is running. `side_started_at` and `started_at` are set. |
| `stopped` | Playback ended cleanly. `ended_at` is set. Terminal. |
| `cancelled` | Queued session abandoned without starting. `ended_at` is set. Terminal. |

**Constraint:** `valid_status CHECK (status IN ('queued', 'playing', 'stopped', 'cancelled'))`.

**Uniqueness:** A user can have at most one session per non-terminal status:
```sql
CREATE UNIQUE INDEX idx_playback_sessions_active_playing
  ON playback_sessions (user_id) WHERE status = 'playing';
CREATE UNIQUE INDEX idx_playback_sessions_active_queued
  ON playback_sessions (user_id) WHERE status = 'queued';
```

Producers MUST cancel/stop an existing same-status session before transitioning a new one into it.

---

## Event Types

There are exactly five canonical event types. The set is closed and enforced by a CHECK constraint:

```sql
CONSTRAINT valid_event_type CHECK (event_type IN (
  'session_queued', 'side_changed', 'playback_started',
  'playback_stopped', 'session_cancelled'
))
```

| Event | Trigger | Resulting session row state |
|---|---|---|
| `session_queued` | Album identified, session created in `queued` status | INSERT row, `status: queued`, `side_started_at: NULL` |
| `playback_started` | User (or hub button) starts playback | UPDATE `status: playing`, `started_at: now()`, `side_started_at: now()` |
| `side_changed` | Side flip mid-session | UPDATE `current_side`; if `status='playing'`, also set `side_started_at: now()` |
| `playback_stopped` | Playback ended | UPDATE `status: stopped`, `ended_at: now()` |
| `session_cancelled` | Queued session abandoned without starting | UPDATE `status: cancelled`, `ended_at: now()` |

**Stop events.** `playback_stopped` is the natural place to attribute elapsed time, since `started_at` is set and `ended_at` is set in the same handler. See [Relationship to `listening_history`](#relationship-to-listening_history).

---

## Event Payloads

The `payload` JSONB column carries event-specific data beyond what's in `playback_sessions`. Authoritative state lives on the session row — the payload exists for subscribers that need event-time context without an extra query.

| Event | Typical payload |
|---|---|
| `session_queued` | `{ library_album_id, album_title, album_artist, current_side }` |
| `playback_started` | `{}` |
| `side_changed` | `{ side }` |
| `playback_stopped` | `{}` |
| `session_cancelled` | `{}` |

**Notes:**
- Cover art, tracks snapshot, and side durations live on the session row (denormalized for hubs and widgets) — they are NOT duplicated into the `session_queued` payload.
- Future producers MAY add fields to the payload as long as existing consumers ignore unknown keys (forward-compatibility).

---

## Source Types

Every event MUST declare its origin so observers can attribute the action correctly:

```sql
CONSTRAINT valid_source_type CHECK (source_type IN ('app', 'hub', 'web', 'api'))
```

| `source_type` | Producer |
|---|---|
| `app` | Consumer mobile app (iOS / Android) or Apple TV app |
| `hub` | Saturday Hub firmware (via edge function gateway) |
| `web` | Future web client |
| `api` | Server-side jobs, admin tools, integrations |

`source_device_id` is a nullable FK to `units(id)` that identifies the specific physical hub that emitted a `hub`-sourced event. Apps leave it NULL.

The same fields appear on `playback_sessions` (`queued_by_source`, `queued_by_device_id`, `started_by_source`, `started_by_device_id`) so the session row records who queued and who started independently — for example, a hub-queued session that the user started manually from the app will have `queued_by_source='hub'` and `started_by_source='app'`.

---

## Session Row Reference

Key columns on `playback_sessions` that producers and subscribers should know about. (See `shared-supabase/schema/SCHEMA.md` for the full definition.)

| Column | Purpose |
|---|---|
| `status` | One of `queued`, `playing`, `stopped`, `cancelled` |
| `current_side` | `'A' \| 'B' \| 'C' \| 'D'` |
| `side_started_at` | Authoritative timestamp for "when did this side start playing?". NULL when queued. Reset on `side_changed` while playing. |
| `started_at` | When playback first started (set on `playback_started`, not reset by side changes). |
| `ended_at` | When the session terminated (set on `playback_stopped` / `session_cancelled`). |
| `tracks` | JSONB snapshot of the current side's tracks (positions, titles, durations). The single source of truth for track progression math. |
| `side_a_duration_seconds`, `side_b_duration_seconds` | Total side runtime, for hub countdown LEDs. |
| `current_track_index`, `current_track_position`, `current_track_title` | Derived progression state, written by the foregrounded app or the `update-track-progression` cron. |
| `queued_by_source`, `started_by_source` | Provenance fields — see [Source Types](#source-types). |

**Constraints worth knowing:**
- `valid_side CHECK (current_side IN ('A', 'B', 'C', 'D'))` — sides beyond D are not currently supported by this protocol.
- Unique partial indexes on `(user_id) WHERE status='queued'` and `WHERE status='playing'` enforce single-active-session-per-status.

---

## Hub Broadcast Trigger

When a row is inserted into `playback_events`, the `broadcast_playback_event_to_hubs` trigger publishes the event to every online hub owned by the user, using the existing `device:<mac>` channel pattern:

```sql
-- Simplified — see migration 20260313120000_mobile_playback_sessions.sql
CREATE TRIGGER on_playback_event_broadcast
  AFTER INSERT ON playback_events
  FOR EACH ROW EXECUTE FUNCTION broadcast_playback_event_to_hubs();
```

The trigger:
1. Finds all `devices` joined through `units` where `units.consumer_user_id = NEW.user_id` AND `units.is_online = true`.
2. For each device, builds channel name `device:<mac>` (colons replaced with dashes) and emits a Realtime broadcast with envelope:
   ```json
   {
     "event": "playback_event",
     "payload": {
       "event_type": "<event_type>",
       "session_id": "<uuid>",
       "payload": <event payload>,
       "source_type": "<source>",
       "created_at": "<iso8601>"
     }
   }
   ```

**Why this matters for firmware:** Hub firmware does NOT subscribe to `playback_events` directly. It receives playback state on its existing `device:<mac>` device-command channel, alongside provisioning and OTA messages. The `event` field on the broadcast envelope distinguishes `playback_event` from `device_command`.

---

## Authorization (RLS)

Both tables enforce Row Level Security keyed off `auth.uid()` → `users.auth_user_id`:

- Authenticated users can SELECT/INSERT/UPDATE/DELETE only their own sessions.
- Authenticated users can SELECT/INSERT only their own events. (Events are append-only — there is no UPDATE policy.)
- The `service_role` has full access on both tables (for edge functions and cron).

Edge functions that publish events on behalf of hubs MUST use the service role and set `user_id` correctly based on `unit → consumer_user_id` resolution.

---

## Sync Mechanisms

How each event reaches each consumer:

| Mechanism | Used by | Latency | Works when |
|---|---|---|---|
| **Supabase Realtime** (WebSocket) | Apps in foreground, hubs | Sub-second | Connection is live |
| **FCM / APNs Push** | Mobile apps in background or terminated | 1–5s | OS push delivery |
| **ActivityKit Push** (iOS) | iOS Live Activity on lock screen | 1–5s | Live Activity is active |
| **Query `playback_sessions`** | Any client, any state | ~200ms | Catch-up on launch or reconnection |

### Event-specific delivery

| Event | Realtime | FCM Push | ActivityKit Push |
|---|---|---|---|
| `session_queued` | Auto | Yes — alert user on backgrounded devices | No (no Live Activity yet) |
| `playback_started` | Auto | No | Yes (start/update Live Activity) |
| `side_changed` | Auto | No | Yes (if playing) |
| `playback_stopped` | Auto | Yes — notify backgrounded devices | Yes (end Live Activity) |
| `session_cancelled` | Auto | No | No |

---

## Track Progression

**Track position is NOT an event.** It is derived state computed deterministically from `side_started_at` + the `tracks` JSONB snapshot.

- **Foregrounded apps** calculate locally every second and UPDATE `current_track_index/position/title` on `playback_sessions` when a boundary is crossed.
- **Server cron** (`update-track-progression` edge function, ~30s interval) performs the same calculation for backgrounded sessions and sends ActivityKit push updates.
- **Any capable device** can write the update. The calculation is deterministic, so concurrent writers converge — no leader election needed.

---

## Relationship to `listening_history`

`playback_sessions` and `listening_history` serve different purposes and MUST both be written:

| Table | Purpose | Lifetime |
|---|---|---|
| `playback_sessions` | What is playing right now (or recently). Powers UI, widgets, hub LEDs. | Ephemeral — overwritten by next session. |
| `listening_history` | Append-only record of plays for analytics, recommendations, "recently played". | Permanent. |

**Duration attribution.** When a session transitions to `stopped` or `cancelled`, the same handler SHOULD compute elapsed seconds (`ended_at - started_at`, clamped at the album's total runtime) and write it to the corresponding `listening_history` row's `play_duration_seconds` column. Without this, downstream analytics (e.g. "minutes listened") will be zero.

Producers MAY also record `completed_side` on `listening_history` based on the session's final `current_side`.

---

## Implementation Reference

| Repository / project | File | Purpose |
|---|---|---|
| shared-supabase | `supabase/migrations/20260313120000_mobile_playback_sessions.sql` | Canonical schema for both tables, broadcast trigger, RLS |
| shared-supabase | `supabase/migrations/20260314120000_mobile_track_progression.sql` | Adds `current_track_index` and related progression columns |
| shared-supabase | `supabase/functions/update-track-progression/` | Cron-driven track progression updater |
| saturday-mobile-app | `lib/repositories/playback_session_repository.dart` | Reference implementation of `queueSession`, `startSession`, `stopSession`, `cancelSession`, `changeSide` |
| saturday-mobile-app | `lib/providers/playback_sync_provider.dart` | Realtime subscription and event handler |

When implementing a new producer (firmware, web, integration), match the event-type/payload shape used by the consumer app for forward compatibility.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 1.0.0 | 2026-05-12 | Initial publication. Documents the model introduced by migration `20260313120000_mobile_playback_sessions.sql` (April 2026). |
