# Saturday Playback Event Protocol

**Version:** 2.0.0
**Last Updated:** 2026-06-12
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
14. [Deprecation: `stopped` status](#deprecation-stopped-status)
15. [Producer Migration Notes (v1 → v2)](#producer-migration-notes-v1--v2)
16. [Version History](#version-history)

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

A session has three non-terminal statuses (`queued`, `playing`) and one terminal status (`cancelled`). `stopped` exists for legacy rows but is no longer reachable from any event (see [Deprecation: `stopped` status](#deprecation-stopped-status)).

```
                            side_changed / playback_stopped
                           ┌──────────────────────────────┐
                           │                              │
                           ▼                              │
       session_queued  ┌─────────┐  playback_started  ┌─────────┐
   (none) ────────────►│ queued  │───────────────────►│ playing │
                       └─────────┘                    └─────────┘
                            │
                            │ session_cancelled
                            ▼
                       ┌───────────┐
                       │ cancelled │
                       └───────────┘
```

| Status | Meaning |
|--------|---------|
| `queued` | Album is on the stand, no timer running. `side_started_at` is NULL. Entered via `session_queued`, `side_changed` (from playing), or `playback_stopped` (from playing). |
| `playing` | Timer is running on the current side. `side_started_at` is set; `started_at` is set the first time the session ever entered `playing` and preserved across subsequent resumes. |
| `cancelled` | Session terminated. `ended_at` is set. Total play time across all play windows is recorded on `play_seconds_total`. Terminal. |
| `stopped` | **Deprecated.** No event leads here. Pre-2.0 rows retain this status; new sessions terminate as `cancelled`. |

**Saturday model.** A session lives as long as the record sits on the stand. Stopping playback or finishing a side does NOT end the session — the record stays queued, awaiting the listener to drop the needle (on the same side, the other side, or whatever side they choose). The session terminates only on an explicit clear, an off-stand detection, or a replacement record being placed on the stand.

**Constraint:** `valid_status CHECK (status IN ('queued', 'playing', 'stopped', 'cancelled'))` (kept for legacy compatibility).

**Uniqueness:** A user can have at most one session per non-terminal status:
```sql
CREATE UNIQUE INDEX idx_playback_sessions_active_playing
  ON playback_sessions (user_id) WHERE status = 'playing';
CREATE UNIQUE INDEX idx_playback_sessions_active_queued
  ON playback_sessions (user_id) WHERE status = 'queued';
```

A user MAY have one `queued` and one `playing` session simultaneously (e.g. a hub queued album Y while the user is playing album X). When a producer wants to start a new session, it MUST cancel any existing same-user session via `session_cancelled` (the trigger gracefully handles a session that is currently `playing` — see [Server-side state derivation](#server-side-state-derivation)).

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
| `session_queued` | Album identified, producer wants a new session in `queued` status | Producer INSERTs the session row with `status: queued`, `side_started_at: NULL`. The trigger is a no-op (the row already carries the correct state). |
| `playback_started` | Listener drops the needle (app, Apple TV, or hub button) | UPDATE `status: playing`, `started_at: COALESCE(started_at, now())`, `side_started_at: now()` |
| `side_changed` | Side ended naturally, listener picked a different side, or hub physical flip-button | UPDATE `status: queued`, `current_side: payload.side`, `side_started_at: NULL`; accumulate the just-elapsed playing window into `play_seconds_total` |
| `playback_stopped` | Listener tapped Stop the record (no side change) | UPDATE `status: queued`, `side_started_at: NULL`; accumulate the just-elapsed playing window into `play_seconds_total` |
| `session_cancelled` | Listener cleared the stand, hub detected the record off-stand, or a new record replaces this one | UPDATE `status: cancelled`, `ended_at: now()`, `side_started_at: NULL`; if `side_started_at` was non-NULL, accumulate the open window into `play_seconds_total` first |

**`side_changed` semantics.** The event always lands in `queued`. It applies from either `playing → queued` (auto-advance, manual flip, hub button) or `queued → queued` (listener picks a different side before dropping the needle). The payload's `side` field is the target side — it MAY equal the current side (e.g. a hub flip-button on a one-sided test record), in which case the row's `current_side` is left unchanged but the status still transitions.

**`playback_stopped` semantics.** Stops the running timer. The session remains alive in `queued` with the same `current_side`. To resume, emit `playback_started`. To terminate, emit `session_cancelled`.

**`session_cancelled` is the only terminal event.** Producers do NOT need to chain `playback_stopped` before `session_cancelled` — the trigger handles a "cancel from playing" gracefully by accumulating the open window into `play_seconds_total` and then setting status/ended_at in a single UPDATE.

**Listening history attribution.** See [Relationship to `listening_history`](#relationship-to-listening_history) — the duration written to `listening_history.play_duration_seconds` is the session's `play_seconds_total` (sum of all play windows), not `ended_at - started_at`.

### Server-side state derivation

Producers do NOT update `playback_sessions` directly for state transitions. They INSERT canonical events; a single AFTER INSERT trigger on `playback_events` (`apply_playback_event`) derives the session-row state from the event type and payload. This guarantees that:

- `play_seconds_total` accumulates correctly across multiple pauses and resumes.
- `side_started_at` is always NULL when status is `queued` (no stale artifacts).
- A `session_cancelled` arriving while the session is in `playing` is handled in a single trigger pass — the producer never has to know the prior status.
- Hub firmware, mobile, Apple TV, and admin tools converge on identical session state regardless of which device emits which event.

The only direct mutation a producer performs on `playback_sessions` is the INSERT in `queueSession` (since that creates the row). All later changes flow through `playback_events`.

---

## Event Payloads

The `payload` JSONB column carries event-specific data beyond what's in `playback_sessions`. Authoritative state lives on the session row — the payload exists for subscribers that need event-time context without an extra query.

| Event | Typical payload | Required fields |
|---|---|---|
| `session_queued` | `{ library_album_id, album_title, album_artist, current_side }` | none (informational) |
| `playback_started` | `{}` | none |
| `side_changed` | `{ side }` | `side` (the post-event target side; the trigger writes `current_side = payload.side`) |
| `playback_stopped` | `{}` | none |
| `session_cancelled` | `{}` | none |

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
| `status` | One of `queued`, `playing`, `cancelled` (or legacy `stopped` — see [Deprecation: `stopped` status](#deprecation-stopped-status)) |
| `current_side` | `'A' \| 'B' \| 'C' \| 'D'` |
| `side_started_at` | Authoritative timestamp for the open play window. NULL when queued. Set on `playback_started`; cleared on `side_changed`, `playback_stopped`, and `session_cancelled`. |
| `started_at` | When playback first started. Set on the FIRST `playback_started` for the session and preserved across subsequent resumes — `apply_playback_event` uses `COALESCE(started_at, now())`. |
| `play_seconds_total` | **Sum of all play-window durations** for this session. Accumulated by the trigger on every `side_changed`, `playback_stopped`, and `session_cancelled` that closes an open window. This — not `ended_at - started_at` — is the canonical "minutes listened" value. |
| `ended_at` | When the session terminated (set only on `session_cancelled`). |
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

- **Foregrounded apps** calculate locally every second and UPDATE `current_track_index/position/title` on `playback_sessions` when a boundary is crossed. Track-progression writes are the only direct session-row mutations producers perform after `queueSession`.
- **Server cron** (`update-track-progression` edge function, ~30s interval) performs the same calculation for backgrounded sessions and sends ActivityKit push updates. The cron's WHERE clause MUST filter on `status = 'playing'` so paused sessions don't advance.
- **Any capable device** can write the update. The calculation is deterministic, so concurrent writers converge — no leader election needed.

---

## Relationship to `listening_history`

`playback_sessions` and `listening_history` serve different purposes:

| Table | Purpose | Lifetime |
|---|---|---|
| `playback_sessions` | What is playing right now (or recently). Powers UI, widgets, hub LEDs. | Ephemeral — overwritten by next session. |
| `listening_history` | Append-only record of plays for analytics, recommendations, "recently played". | Permanent. |

Producers do NOT write to `listening_history` directly. A server trigger (`sync_listening_history_from_playback_event`) maintains it from canonical playback events:

| Event | Effect on `listening_history` |
|---|---|
| `playback_started` (first one for the session) | INSERT row keyed by `session_id` with `played_at = started_at` |
| `playback_started` (subsequent resumes) | No-op — `ON CONFLICT (session_id) DO NOTHING` |
| `side_changed`, `playback_stopped` | No-op — these are mid-session pauses |
| `session_cancelled` | UPDATE row with `play_duration_seconds = session.play_seconds_total`, `completed_side = session.current_side` |

**Duration attribution under the v2 protocol.** `play_seconds_total` (sum of all play windows on the session) is what gets written to `listening_history.play_duration_seconds` — not `ended_at - started_at`, which would over-count every pause gap. Pre-v2 stopped sessions retain the duration values backfilled by the v1 listening-history migration.

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

## Deprecation: `stopped` status

In v1 of this protocol, `playback_stopped` set `status = 'stopped'` and was the terminal event for a played session. In v2, `playback_stopped` is non-terminal (it pauses the open play window without ending the session) and `session_cancelled` is the only terminal exit from a non-terminal status.

The `stopped` value remains in the schema CHECK constraint for compatibility with rows written under v1. The v2 trigger `apply_playback_event` never produces it. Consumers SHOULD treat `stopped` as equivalent to `cancelled` for read-side purposes (both indicate a session that is no longer active).

The duration backfill in migration `20260520120000_shared_listening_history_from_playback_events.sql` already attributed duration for legacy `stopped` rows.

---

## Producer Migration Notes (v1 → v2)

Pre-v2 producers should adopt the following changes before deploying clients that depend on the v2 trigger:

| Producer concern | v1 behavior | v2 behavior |
|---|---|---|
| Stop a playing session and end it | Emit `playback_stopped` (terminal) | Emit `session_cancelled` (the trigger handles the open-window accumulation in one pass) |
| Pause playback without ending the session | Not supported — `playback_stopped` was terminal | Emit `playback_stopped`. Session goes to `queued` with same side. Resume via `playback_started`. |
| Advance to another side mid-session | Emit `side_changed`; session stayed in `playing` | Emit `side_changed` with `payload.side`. Session goes to `queued`. To start the new side, emit `playback_started`. |
| Hub physical flip button (immediate flip-and-resume) | One event: `side_changed` | Two events in sequence: `side_changed` + `playback_started` |
| Direct UPDATEs to `playback_sessions` for state changes | Required (producer sets status, side_started_at, ended_at) | Forbidden — only the `apply_playback_event` trigger writes status, side_started_at, ended_at, play_seconds_total. Producers only INSERT the session row in `queueSession` and may UPDATE track-progression fields. |
| Off-stand / record-removed detection | Emit `playback_stopped` | Emit `session_cancelled` (the trigger gracefully accumulates the open window if status was `playing`) |
| Listening history attribution | Producer wrote `play_duration_seconds` directly on stop | Trigger writes it from `session.play_seconds_total` on `session_cancelled` |

If a v1 producer cannot be updated immediately and continues to emit `playback_stopped` for "session ended," the cloud will treat it as a pause: the session will sit in `queued` until a `session_cancelled` arrives. This is recoverable but leaves zombie queued sessions; coordinate firmware/AppleTV/web rollouts with this in mind.

---

## Version History

| Version | Date | Changes |
|---|---|---|
| 2.0.0 | 2026-06-12 | Sessions now live as long as the record is on the stand. `playback_stopped` and `side_changed` both become non-terminal (`playing → queued`). `session_cancelled` is the only terminal event. New `play_seconds_total` column accumulates play time across multiple play windows. Server-side trigger `apply_playback_event` derives session state from events; producers no longer UPDATE state columns directly. `stopped` status deprecated. |
| 1.0.0 | 2026-05-12 | Initial publication. Documents the model introduced by migration `20260313120000_mobile_playback_sessions.sql` (April 2026). |
