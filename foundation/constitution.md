# Saturday! Constitution

A short charter for code in this repository. The brand framework and design system foundations live in companion documents (see References); this document is the operational translation for engineering.

Read this before adding components, screens, copy, or interaction patterns. It exists to keep the codebase from drifting toward streaming-app conventions while staying useful as a working reference.

---

## References

- Brand operating framework — `./shared-docs/foundation/operating-framework.md`
- Design system foundations — `./shared-docs/foundation/foundations.md`
- Wordmark (canonical SVG) — `./shared-docs/foundation/wordmark.svg`
- App icon (canonical SVG) — `./shared-docs/foundation/icon.svg`
- Figma file — [Saturday! — Design System Foundations](https://www.figma.com/design/6WT3fL7Pl0F4fwJCaPJl40/Saturday--%E2%80%94-Design-System-Foundations?node-id=0-1&p=f&t=zV7L0Rp4Z0SnJOE3-0)
- Variable collections in Figma — Color (Light / Dark modes), Spacing, Motion

When this document and the foundations doc diverge, the foundations doc wins. Update this file.

---

## The posture

Saturday! is a thoughtful host, never a controlling host. The system rarely speaks. When it speaks, it is specific, observational, restrained, and warm without performance. Reverent toward the records and the ritual; warm-hearted about everything else. Built for return rather than acquisition.

The single most important rule to internalize: *the system has no color of its own. The music brings the color.* Almost every code-level decision in a listening surface flows from that — color, atmosphere, what the system asserts vs. what it borrows from the album playing.

---

## The two questions (code review)

Before merging any PR that adds a component, screen, behavior, or user-facing string:

1. **What primitive is this expressing, and does it belong here?**
2. **Is the absence of this thing more Saturday! than its presence?**

If the answer to question 2 is yes, the change should not be merged.

---

## Banned patterns

The code does not implement any of the following, ever. Each maps to a veto in the design foundations.

- **Toggle switches.** State is communicated by text values (`off`, `local only`, `connected`).
- **Loading spinners and progress bars.** Loading is held space — a paper-tone skeleton. Content arrives via the `arrive` motion gesture once ready.
- **Confirmation modals before destructive actions.** User actions are sovereign. Destructive actions proceed; undo is the recovery channel.
- **Toast notifications and snackbars.** State changes are reflected in the surface itself, never announced.
- **Push notifications for promotion, engagement, or algorithmic recommendation.** No "come back," no "we picked something for you," no "you haven't listened in a while," no feature announcements. The system does not summon the listener to the app. (Session-enriching push is allowed and specified in the Push notifications section below.)
- **Badges showing unread counts.** Decorative grouping badges are fine; counts are not.
- **Star ratings, heart icons, like buttons, score displays.** No rating system exists.
- **"For you," "Recommended," "Trending," "Popular," "Top tracks," "More like this" surfaces.** No algorithmic recommendation feeds.
- **Skip / next / shuffle buttons in listening surfaces.** Records play through; the listener controls the turntable directly.
- **Queue UI of any kind.** The `Session` primitive replaces it.
- **Progress indicators in the listening room.** Time is not a Saturday! quantity. The archive may show duration as factual data when relevant, never as a bar.
- **Spring or bounce animations.** Motion uses three named curves only — none of them spring.
- **Audio-reactive visuals** (spectrum analyzers, waveforms, beat-sync effects).
- **Emoji in any user-facing string.**
- **Exclamation points anywhere except in the literal string `Saturday!` (the wordmark).**
- **The word "user" in user-facing copy.**
- **Status indicators on hardware** (power LEDs, sync LEDs, error blinks). The LED canvas is a writeable surface, not a status display.

---

## Required patterns

- **Loading uses a `<Skeleton>` component** that holds layout in paper-tone shapes. Content replaces it via the `arrive` motion gesture.
- **Errors are factual sentences.** No "Sorry," "Oops," or "Something went wrong." Example: `"Stand isn't responding."`
- **All copy is sentence case.** No Title Case. No ALL CAPS (except for mono technical data sourced as-is — matrix numbers, catalog labels).
- **Album titles render in serif italic** in body text. Artist names render in sans.
- **Numbers in narrative use the witness register** — spelled out when they sit naturally in prose (`"twenty-three plays"`). Numbers in tabular data are numeric and rendered in mono.
- **The wordmark is rendered from the canonical SVG**, never typeset. It's the only place an exclamation point appears in the entire product.

---

## Push notifications

Push is a vessel for session-enriching signals only. The product never uses push to promote the app, market features, or re-engage an inactive listener.

**Allowed categories** (listener has opted in; the push serves the session):

- *Session courtesies* — a record's side is about to end; the next record in a composed session is ready; an invitation pulse just landed on a crate the listener might want to know about.
- *State signals* — a record was placed on the stand; the stand isn't responding; a crate's battery is low; hardware needs attention.
- *Listener-configured reminders* — a morning briefing the listener scheduled; a time-of-day briefing the listener set up for that day's likely listening.

**Required posture for every push:**

- **Opted in.** Off by default. Granular per-category controls in preferences.
- **Quiet by default.** No sound, no haptic stronger than a single light tap, no lock-screen takeover language. Use iOS time-sensitive interruption-free / Android quiet channel where the platform supports it.
- **Follows §6.6 invitation rules** — single beat, no badge count, no escalation, no follow-up if ignored. *Walking away is data* applies to push as much as to UI.
- **Voice follows §10** — sentence case, no exclamation, no marketing, no "user." Factual and observational.
- **Never an engagement loop.** No tap-through metrics, no A/B-testing push timing, no harder push to inactive listeners. The system measures presence by listening, not by app return.

**Test strings:**

| String | Verdict |
|---|---|
| `"Side A ending in three minutes."` | Correct — session courtesy. |
| `"Coltrane's Sound is on the stand."` | Correct — state signal. |
| `"Crate B battery low."` | Correct — state signal. |
| `"Sunday morning — three records on the third shelf."` | Correct — listener-scheduled. |
| `"We miss you! Come back."` | Wrong — re-engagement. |
| `"You'd love this Coltrane record!"` | Wrong — algorithmic + exclamation. |
| `"You haven't logged a session in 5 days."` | Wrong — engagement guilt. |
| `"New feature: archive cleanup!"` | Wrong — feature marketing. |
| `"Rate Saturday! in the App Store."` | Wrong — self-promotion. |

---

## Vocabulary

### Domain language

The data model, types, database tables, API endpoints, and component props use the Saturday! term — never the streaming-app term.

| Saturday! term   | Streaming-app term (do not use) |
|------------------|---------------------------------|
| `session`        | queue, playlist                 |
| `collection`     | library                         |
| `archive`        | history, library                |
| `slot`           | (no equivalent — Saturday!-specific) |
| `stand`          | now playing area                |
| `witness`        | (no equivalent — Saturday!-specific) |
| `invitation`     | recommendation, notification    |
| `record`         | track, song (when referring to an LP) |
| `listener`       | user                            |

### Component vocabulary

Allowed components map to Saturday! domain concepts:

- `<Stand>` — the now-playing surface
- `<Slot>` — a position in a crate
- `<Session>` — a composed listening sequence
- `<WitnessEntry>` — a per-record narrative observation
- `<Invitation>` — a single-pulse surfaced suggestion
- `<Skeleton>` — held loading space
- `<RecordCard>` — a record's reference card (archive, sessions)
- `<RoomEyebrow>` — the wayfinding label at the top of a room screen

Disallowed components (don't add them; the system doesn't need them):

- `<Toggle>` / `<Switch>` — use `<StatefulValue>` or plain text
- `<Spinner>` / `<Loader>` / `<ProgressBar>`
- `<Toast>` / `<Snackbar>`
- `<Rating>` / `<Stars>` / `<LikeButton>`
- `<ConfirmDialog>`
- `<Queue>`
- `<ForYou>` / `<Recommendation>` / `<Trending>`
- `<UnreadBadge>`

---

## Tokens

All color, spacing, and motion values come from the design system. Tokens are defined in the Figma file (linked above) and consumed in code via [export mechanism TBD: Style Dictionary, custom tooling, etc.]. Hardcoded values for any of these properties are not allowed.

### Color

Modes: `Light`, `Dark`. Mode is selected automatically when the room's ambient-light sensor is available, falls back to system preference, and can be pinned by the listener.

| Token              | Light      | Dark       | Use                                |
|--------------------|------------|------------|------------------------------------|
| `paper`            | `#F6F5F2`  | `#1A1817`  | Body background                    |
| `paper-elevated`   | `#FFFFFF`  | `#232120`  | Cards, raised surfaces             |
| `ink`              | `#1A1817`  | `#F4F2EC`  | Primary text                       |
| `ink-secondary`    | `#5A5854`  | `#B4B2AC`  | Secondary text, metadata           |
| `ink-tertiary`     | `#8A8884`  | `#7A7874`  | Tertiary text, captions, hints     |
| `border-quiet`     | `#E8E6E0`  | `#2A2826`  | Hairlines, dividers                |
| `border-strong`    | `#C8C6C0`  | `#3F3D3A`  | Stronger divisions                 |
| `felt`             | `#C25A2A`  | `#C25A2A`  | Identity moments only (working)    |

Rules:
- **The archive uses paper/ink only.** Never album-derived color.
- **The listening room uses album-derived atmospheric color** on backgrounds and edges only. Never on UI chrome.
- **The felt orange appears in identity moments only.** Never in listening surfaces.
- **Felt orange and album-derived color never appear on the same screen.**
- **No semantic state colors.** No success-green, error-red, warning-amber. State is communicated by text, position, or motion.
- **No hardcoded color values.** Use tokens.

### Spacing

Linear 4-pixel scale. Use only these stops.

| Token       | Px  | Use                                                       |
|-------------|-----|-----------------------------------------------------------|
| `space-1`   | 4   | Tight component-internal                                  |
| `space-2`   | 8   | Component-internal                                        |
| `space-3`   | 12  | Between related elements                                  |
| `space-4`   | 16  | Base gap                                                  |
| `space-6`   | 24  | Between groups within a section                           |
| `space-8`   | 32  | Between sections                                          |
| `space-12`  | 48  | Between major regions                                     |
| `space-16`  | 64  | Atmospheric page-level breathing                          |
| `space-24`  | 96  | Large compositional space; listening room uses this often |

Rules:
- **Use only scale stops.** Values like `13px` or `19px` are not allowed — change the layout or change the scale.
- **The listening room reaches for the high end** (atmospheric); the archive uses tight stops within regions and high stops between regions.

### Type

Three faces; two weights only (`400` Regular, `500` Medium). Production candidates noted; working picks are open-source approximations available today.

| Token         | Working pick      | Production candidate    | Use                                   |
|---------------|-------------------|-------------------------|---------------------------------------|
| `font-sans`   | Inter Tight       | Söhne (Klim)            | UI chrome, labels, metadata           |
| `font-serif`  | Source Serif 4    | Tiempos Text (Klim)     | Album titles, narrative, witness      |
| `font-mono`   | JetBrains Mono    | Söhne Mono (Klim)       | Matrix numbers, timings, gear chain   |

Line height and measure (from foundations §4.3):

| Use                          | Line height | Measure  |
|------------------------------|-------------|----------|
| Serif body / witness         | `1.65`      | 60–65 ch |
| Sans body                    | `1.5`       | 70–80 ch |
| Sans label / metadata        | `1.3–1.4`   | —        |
| Mono technical data          | `1.4`       | —        |

Working type scale, extracted from the reference experiences. Not yet canonized in foundations §3 — treat as a working set, revisit when building components.

| Token                    | Size | Family       | Use                                       |
|--------------------------|------|--------------|-------------------------------------------|
| `text-eyebrow`           | 11   | sans         | Wayfinding labels, section eyebrows       |
| `text-meta`              | 12   | sans         | Metadata, captions                        |
| `text-body-small`        | 13   | sans         | UI prose, helper text                     |
| `text-body`              | 14   | sans / serif | Body, archive narrative                   |
| `text-prose`             | 17   | serif        | Long-form witness narrative               |
| `text-section`           | 26   | serif        | Section headings                          |
| `text-title-archive`     | 28   | serif        | Archive page titles                       |
| `text-title-listening`   | 38   | serif        | Listening-room album titles               |

Rules:
- **Sentence case throughout.** Never Title Case. Never ALL CAPS (except mono technical data sourced as-is — matrix numbers, catalog labels).
- **Italic in serif body** carries temporal witness language. Used judiciously.
- **Album titles render in serif italic** in body. Artist names in sans.
- **The wordmark is rendered from the canonical SVG**, never typeset.

### Motion

Duration and easing tokens:

| Token                   | Value                              |
|-------------------------|------------------------------------|
| `duration-quick`        | `180ms`                            |
| `duration-standard`     | `320ms`                            |
| `duration-slow`         | `1200ms`                           |
| `duration-pulse`        | `1500ms`                           |
| `duration-stand-fade`   | `30000–60000ms` (working range)    |
| `ease-arrive`           | `cubic-bezier(0.16, 1, 0.3, 1)`    |
| `ease-recede`           | `cubic-bezier(0.7, 0, 0.84, 0)`    |
| `ease-blend`            | `cubic-bezier(0.45, 0, 0.55, 1)`   |

Gesture → token mapping:

| Gesture     | Duration token         | Curve token   | When to use                            |
|-------------|------------------------|---------------|----------------------------------------|
| `arrive`    | `duration-standard`    | `ease-arrive` | Content lands, screens appear          |
| `recede`    | `duration-standard`+   | `ease-recede` | Content dismissed, invitations expire  |
| `pulse`     | `duration-pulse`       | `ease-blend`  | Single-beat invitation (once only)     |
| `settle`    | `duration-quick`       | `ease-blend`  | Layout reflow without urgency          |
| `blend`     | `duration-slow`        | `ease-blend`  | Color transitions (stand glow)         |
| `override`  | `0ms`                  | none          | User-initiated state change            |
| `hold`      | —                      | —             | Stillness; the system at rest          |

Rules:
- **Pulse animates exactly once.** Never `animation-iteration-count: infinite` on a pulse. The exception is the rest-state LED brightness, which is constant, not animated.
- **Override interrupts any in-progress gesture instantly.** No completion animation, no reverse, no spring-back. Cancel the transition; reflect the new state.
- **`prefers-reduced-motion` reduces durations to ~80–120 ms** across all gestures and removes pulse curves entirely (single appearance instead of a brightness curve).
- **No motion that demands a response.** A pulse that repeats until tapped is a notification. Saturday! has no notifications.

---

## Voice in code

All user-facing strings follow §10 of the foundations doc (Voice & Copy). Operational rules for engineering:

- **Sentence case.** Never Title Case. Never ALL CAPS (except in mono technical data — matrix numbers, catalog labels — sourced as-is).
- **No exclamation points** except in the literal string `Saturday!`.
- **No emoji.** In any user-facing string.
- **No greetings.** No "Welcome back," "Hi," "Hello."
- **No encouragement or praise.** No "Great choice," "Nice pick."
- **No apologies.** Errors are factual.
- **No confidence indicators.** No "We think...," "Probably," "Based on your listening..."
- **No marketing voice.** No "Featured," "Curated," "Just for you."
- **No "user."** The listener is *the listener*, *the collector*, or an implied subject.
- **No system self-reference where avoidable.** Prefer "The room noticed" over "We noticed." Prefer no subject at all where natural.

### Test strings

| String | Verdict |
|---|---|
| `"The stand is empty."` | Correct empty state. |
| `"Coltrane crate, often follows what's playing now."` | Correct invitation. |
| `"Stand isn't responding."` | Correct error. |
| `"Welcome back!"` | Wrong (greeting + exclamation). |
| `"Try this Coltrane playlist!"` | Wrong (CTA + playlist + exclamation). |
| `"You've played this 23 times! ★★★★★"` | Wrong (you + exclamation + rating). |
| `"Loading…"` | Wrong (no loading copy — use Skeleton). |
| `"Are you sure?"` | Wrong (no confirmation dialogs). |

### The witness register

A specific copywriting mode used in per-record narrative and observational moments. Temporal, observational, no comparison. Italic carries temporal observations.

Examples:
- `"First heard one quiet Saturday in October 2019. Twenty-three plays so far, most after dark."`
- `"Often the second record of an evening — after Mingus, before Davis."`
- `"Acquired from the estate sale in Pasadena, 2018."`

Witness content is co-authored: the system writes observations from passive data (placement events, dates, patterns); the listener writes notes. Both live in the same stream, in the same voice. The listener can edit any system observation. The system never defends its prior version.

---

## Accessibility

These are baseline expectations, not Saturday!-specific. They are not optional.

- **WCAG 2.1 AA contrast minimums everywhere.** The structural palette is verified; album-derived color requires text-color selection by luminance contrast (pick `ink` or `paper`, never interpolate).
- **Touch targets**: minimum 44pt iOS / 48dp Android. The aesthetic preference for small affordances must never override this.
- **Full keyboard navigation.** All actions reachable without a mouse or touch.
- **Screen reader semantics.** The witness register must read sensibly aloud — temporal language is preserved, not flattened to data.
- **`prefers-reduced-motion`** respected by all motion (see Motion section above).
- **Focus visible at all times.** Focus indicators use ink stroke and offset, not color.

---

## Open questions

These are unresolved in the foundations and require team decisions:

- The exact gesture for moving between rooms. Working assumption: horizontal swipe.
- The settings invocation gesture (corner brand mark, pull-down, system gesture).
- The token export mechanism from Figma to code (Style Dictionary, custom tooling, etc.).
- The witness data persistence model (system observations vs. listener notes — same table, different attribution).
- The final felt-orange hex value (`#C25A2A` is a working placeholder pending physical measurement against the actual orange felt).
- Sound and haptics (foundation sections §7 and §8 are still to be written).

---

## Maintaining this document

This constitution is the operational interface between brand and code. Update it when:

- A new banned pattern is added to the foundations.
- The vocabulary changes (a new domain term is named, or a streaming-app term gets a Saturday! equivalent).
- The token structure changes (new tokens, new modes, renamed scales).
- A code-review pattern emerges that catches drift repeatedly.

The foundations doc is the source of truth; this document follows. When they diverge, update this document.
