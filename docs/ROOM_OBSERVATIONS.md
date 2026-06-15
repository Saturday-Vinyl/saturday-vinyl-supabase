# Room observations

A working spec for the quiet, observational lines the **listening room**
surfaces to the listener — what the constitution calls *the room noticed* —
in place of the algorithmic recommendation feeds banned in §"Banned
patterns."

This is not a recommendation engine. It is the room remembering, in the
witness register. Single observation per visit. Walking away is data.

---

## Voice and posture

Read `shared-docs/foundation/constitution.md` first. The lines below are
shaped by it, not by streaming-app conventions.

- **Observational, never prescriptive.** State what happened; never
  suggest what to do.
- **No "For you," "Recommended," "Trending,"** or confidence language
  ("We think…", "Based on your listening…").
- **Album titles in serif italic.** Numbers in narrative spelled out
  ("six times," not "6×").
- **Sentence case, no exclamation,** no greetings, no "user."
- **Absence is fine.** If nothing qualifies under the thresholds below,
  the room shows nothing. The constitution prefers absence to
  over-asserting.

---

## The six categories

Each category names a pattern the room can witness. Per-category
thresholds are deliberately conservative — three occurrences is a
pattern, two is a coincidence.

### 1. Temporal echo *(simple)*

> "Last week around this time, *Sketches of Spain* was on the stand."

What was on the stand on a previous matching weekday + hour.

| | |
|---|---|
| **Data** | `listening_history` only |
| **Threshold** | at least one play in last 60 days at same weekday and within ±2 hours of now |
| **Variants** | 7–14d → "Last week around this time, *{title}* was on the stand." · 28–35d → "A month ago tonight: *{title}*." · 360–370d → "A year ago tonight: *{title}*." |
| **Complexity** | low |

### 2. Sequence echo *(medium)*

> "*Kind of Blue* often comes back after *A Love Supreme*."

Ordered (a → b) pairs that recur often enough to be a pattern.

| | |
|---|---|
| **Data** | `listening_history` only; computed via `LEAD()` window |
| **Threshold** | same ordered pair appears ≥3 times in last 6 months; a ≠ b |
| **Variants** | observational form above · when `b` is currently on the stand: "*{a.title}* tends to follow what's playing now." (closer to invitation — gate more carefully) |
| **Complexity** | medium; materialize as a nightly view if listening volume grows |

### 3. Ritual observation *(medium)*

> "Three Sundays running, jazz before noon."

(Genre × weekday × time-of-day) buckets that recur across distinct weeks.

| | |
|---|---|
| **Data** | `listening_history` ⨝ `albums.genres` (unnested) |
| **Threshold** | same (genre, dow, time-of-day) recurs in ≥3 distinct weeks within last 8 weeks |
| **Variants** | matching-now form when current dow + tod fits the pattern · retrospective form otherwise ("Friday evenings lately have leaned toward soul.") |
| **Complexity** | medium; genres come pre-normalized from Discogs |

### 4. Cratelist quiet *(simple)*

> "The *Cale* cratelist hasn't come off the shelf in a month."

Cratelists the listener owns or co-owns that haven't been touched in a
while. We don't model physical-shelf neighbors, so cratelists stand in
for the closest "shelf" primitive.

| | |
|---|---|
| **Data** | `cratelists` ⨝ `cratelist_items` ⨝ `listening_history` |
| **Threshold** | cratelist has ≥3 items and no item has been played in ≥30 days |
| **Visibility** | only cratelists the listener owns (`created_by = user.id`) |
| **Complexity** | low |

### 5. Witness return *(needs schema lift)*

> *"Rain that night. Side B sounded thicker." — about Astral Weeks, March 14.*

The listener's own past notes, surfaced quietly without being asked for.

| | |
|---|---|
| **Current data** | `library_albums.notes` is a single mutable text blob — no timestamp, no edit history |
| **Migration needed** | new `witness_entries (id, user_id, library_album_id, body, written_at)` plus an "add witness" affordance on album detail |
| **Threshold** | entry is ≥30 days old; prefer entries on albums recently on the stand |
| **Complexity** | medium — but highest payoff per the brand; this *is* the witness register |

### 6. The recurring record *(simple)*

> "*Pet Sounds* has come back six times this season."

Counts, no ranking. Spelled out in narrative.

| | |
|---|---|
| **Data** | `listening_history` only |
| **Threshold** | ≥5 plays in last 90 days |
| **Complexity** | low; overlaps with `get_album_play_count` logic that already exists |

---

## Shared scaffold

One server-side RPC, called once per visit:

```sql
mobile_room_observation()
  returns table (
    kind                    text,        -- discriminator (see below)
    library_album_id        uuid,        -- optional, for tap-through
    album_title             text,        -- for temporal_echo, recurring_record
    album_artist            text,
    cratelist_id            uuid,        -- for cratelist_quiet
    cratelist_name          text,
    days_ago                int,         -- for temporal_echo
    days_since_last_play    int,         -- for cratelist_quiet
    play_count              int          -- for recurring_record
  )
```

**Picking among qualifying candidates.** Each category contributes 0..N
rows to a candidate pool; the function picks one at random
(`ORDER BY random() LIMIT 1`). Random across visits gives natural
variety without needing per-listener "what did we show last time" state.
The function is `VOLATILE` because of `random()`.

**Discriminator (`kind`).** Flutter switches on this to compose the
sentence with the right TextSpans — album titles in serif italic, sans
elsewhere — instead of the server returning pre-composed text. Server
returns data, client renders.

**Authentication.** `SECURITY INVOKER`; the function resolves
`auth.uid()` → `users.id` internally. Listening history is per-user
(not per-library), so the function takes no library parameter.

**Tap-through.** The whole line is tappable: temporal-echo and
recurring-record route to `/library/album/{libraryAlbumId}`,
cratelist-quiet routes to `/library/cratelists/{cratelistId}`. The tap
target is invisible — no underline, no chrome, no button shape — same
quiet affordance as `_LastOnStand`. This is a deliberate departure from
the strictest constitutional reading ("the observation is a sentence,
not a button"); we accepted it because the visual remains a sentence
and the tap is discoverable only by exploration, not announced. Revisit
if it starts to read as a CTA.

---

## Flutter shape

- `lib/models/room_observation.dart` — sealed class hierarchy or
  discriminated record, one variant per `kind`.
- `lib/repositories/room_observation_repository.dart` — wraps the RPC,
  decodes by `kind`.
- `lib/providers/room_observation_provider.dart` — Riverpod
  `FutureProvider`; refetches when user/library changes, not on a
  timer.
- `lib/widgets/home/room_observation.dart` — renders the single line
  using `RichText` + the serif italic style established by
  `_LastOnStand` in `home_screen.dart`.

**Placement.** v1: empty-stand state only, below "Last on the stand."
The occupied-stand state already carries a witness line about the
playing record; layering room-level observations on top crowds the
surface. Revisit if the empty-stand placement reads as too quiet.

---

## Sequencing

| Cut | Categories | Schema changes | Effort |
|---|---|---|---|
| **v1 (this PR)** | 1, 4, 6 | none | small |
| **v2** | + 2, 3 | none | medium |
| **v3** | + 5 | `witness_entries` table + album-detail UI | medium |

---

## Open questions

- **Per-library scoping.** Listening history is per-user; cratelists
  are per-user (creator or co-owner), not per-library. Today's RPC
  honors that. If multi-library households want observations scoped
  per library, listening_history would need to filter by
  `library_album_id`'s `library_id`.
- **Refresh cadence.** v1 fetches once on mount. If a listener stays
  on the room for a long session, the observation goes stale silently
  — which is probably fine (one observation per visit).
- **Existing recommendation surfaces.** `recommendationsProvider`,
  `upNextProvider`, and `serverRecommendationsProvider` predate the
  constitution's bans and still power the now-playing empty-queue
  carousel. Out of scope for this PR; flag for a follow-up.
