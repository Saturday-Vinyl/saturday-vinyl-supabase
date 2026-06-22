# Saturday! — Design System Foundations

A working specification for the system underneath every Saturday! surface — mobile, desktop, and the room itself.

This document encodes the *Operating Framework* as a usable design system. Where the framework says *the system has no color of its own*, this document says what colors that means and how they translate to LEDs. The framework is the principles; this is the substrate everything binds to. Both are required for design decisions.

---

## How to read this

Each section is one **foundation** — a substrate primitive (color, type, motion, etc.) — and includes:

- **Decisions** — what's settled.
- **Rules** — how to use it across surfaces.
- **Vetoes** — what's explicitly out, with the framework principle it implements.
- **Status** — *settled*, *in exploration*, or *contested*. Sections in exploration are working defaults we're committed to refining with real experience.

Foundations are deliberately stricter than components. A foundation decision constrains every component above it. When a component disagrees with a foundation, the foundation wins; if the foundation is wrong, the foundation changes.

---

## §1 Surfaces

Saturday! is multi-surface from day one. Three surfaces are treated as peers, not as primary and secondary:

- **Apps** — iOS, Android, web, desktop. Pixels on a screen, near the listener.
- **The room** — crate LEDs, the now-playing stand. Light in the listening space.
- **Print & packaging** — physical artifacts. Ink on paper, the felt orange on a label.

Every foundation in this document is written to translate across all three. If a primitive can't express itself on the LED canvas or on a printed sleeve insert, it isn't a Saturday! primitive — it's an app convention that drifted in.

Some primitives translate identically across surfaces (the felt orange is the felt orange whether onscreen, on a label, or under good light on actual fabric). Others have surface-specific encodings of the same underlying decision — a "pulse" is a CSS animation on a phone and an intensity curve on an LED, but it's the same gesture. Each foundation makes the cross-surface mapping explicit.

---

## §2 Color

**Status: in exploration.** Structural palette is a working spec; felt orange is awaiting physical match; album-derived and LED rendering are spec-level pending hardware selection.

Color in Saturday! is governed by one rule that overrides every other rule: *the system has no color of its own. The music brings the color.* Everything below encodes that.

The system supports light mode (the paper register — daytime, archive, contemplative use) and dark mode (the room at night — listening posture, dim ambient) as peer surfaces. Mode is selected automatically when the room's ambient-light sensor is available, falls back to system preference, and can be pinned by the user. Both modes are designed with equal care; the rules don't change between them, only the values.

### §2.1 The structural palette

Paper, ink, neutrals. The base everything else sits on. "Almost colorless by design" — recognizable through restraint, not pigment.

| Token | Light mode | Dark mode | Use |
|---|---|---|---|
| `paper` | `#F6F5F2` | `#1A1817` | Body background. The substrate. |
| `paper-elevated` | `#FFFFFF` | `#232120` | Cards, raised surfaces. |
| `ink` | `#1A1817` | `#F4F2EC` | Primary text, ink-on-paper. |
| `ink-secondary` | `#5A5854` | `#B4B2AC` | Secondary text, metadata. |
| `ink-tertiary` | `#8A8884` | `#7A7874` | Tertiary text, captions, hints. |
| `border-quiet` | `#E8E6E0` | `#2A2826` | Hairlines, dividers. |
| `border-strong` | `#C8C6C0` | `#3F3D3A` | Stronger divisions. |

Decisions implicit in these values:

- Paper is *barely off-white* — not pure white (clinical), not cream (vetoed). The tiniest neutral warmth, near-imperceptible. The veto on tan/beige/oat is held by aggressively limiting how warm paper can drift.
- Ink is *not pure black*. A near-black with the same tonal direction as paper, so they read as the same family. Pure black on near-white reads harsh; this combination reads as printed.
- Dark mode is *the room at night*, not a tech-dark. The "paper" of dark mode is a warm, deep neutral, like a lit room with a lamp. The "ink" of dark mode is a warm light — paper-warmth standing in for a light source.
- The neutral ramp is intentionally short. Five steps cover everything. More steps tempt subtle distinctions that read as decoration.

### §2.2 The felt orange

A single value. The brand's only structural color. Referential to the physical orange felt that lines the crates — not abstract "brand orange."

**Status: working value below; final value to be measured from physical felt under good light (~D50, 5000K) and verified across screen, LED, and print.**

| Token | Light mode | Dark mode | Use |
|---|---|---|---|
| `felt` | `#C25A2A` *(working)* | `#C25A2A` *(working)* | Brand mark, identity moments. |

Rules:

- Appears rarely. Brand mark, packaging, print, a quiet companion to the wordmark. Not used to communicate state, emphasis, hover, focus, or any UI semantic.
- Never appears in listening surfaces. Album-derived color owns those.
- Never appears on the same screen as album-derived color. Identity moments and listening moments do not share visual territory.
- Same value in light and dark modes, unless the physical felt looks materially different under dim room light vs. daylight — in which case dark mode gets a separately-measured value, not a programmatic shift.
- Must match the actual felt under good light. The test is physical: a printed chip, a screen, an LED, and the fabric should sit together and read as the same color. If they don't, the values are wrong, not the felt.

To finalize: photograph the actual felt under D50 or D65 lighting (midday window light is close); spot-measure or eyedrop from a calibrated capture; propose final values for digital, print, and LED separately; verify against fabric.

### §2.3 Album-derived dynamic color

The color that enters listening surfaces from album art. This is where most of the color in the product comes from — and it is not the system's color. It is the music's color, on loan to the surface for as long as the music is present.

**Where it appears:**

- The now-playing stand LED — the literal "stand glow" inheriting the album's dominant character.
- Crate slot-marks — quiet derived color marking where the record came from, fading overnight.
- The listening room app — as atmosphere on backgrounds, edges, ambient surfaces. Never as UI chrome.
- Print contexts where a specific record is the subject (a per-record page printed out, say).

**Where it does not appear:**

- The archive room. The archive is paper/ink only. Album art appears as actual cover thumbnails, not as derived atmospherics.
- UI controls of any kind. Buttons, inputs, labels stay ink-on-paper even on listening surfaces.
- Anywhere the felt orange is present.

**Sourcing rules:**

- Derived from album art via dominant-color extraction. Not a single dominant — a small derived palette (primary, secondary, accent) capturing the cover's character.
- Saturation is reduced slightly from the source. Album covers are made for screens; "light filling a room" needs less saturation than "screen pixel" to read true. Exact reduction is calibrated per surface (more for LED, less for screen).
- Luminance is constrained: derived colors never sit so dark they read as ink, never so light they read as paper. The structural palette's hierarchy must remain readable.

**Contrast guards:**

- Text on derived-color backgrounds: the system picks ink or paper for the text by luminance contrast, not by interpolation. No tinted text on tinted backgrounds. The ink/paper hierarchy survives.
- Minimum contrast ratios per the accessibility baseline (assumed; see Operating Framework).

**No-art fallback:** when an album has no available cover, the listening surface uses paper/ink only. No synthesized art. The system doesn't fake what it doesn't know.

### §2.4 LED color rendering

The room's color decisions in physical light, not pixels. Same rules, different medium.

Anchors:

- **Warm room-light reference, ~2700K.** The LEDs render toward "lamp," not "screen." Cool blue-white is wrong even for cool-toned album art — the room is the medium, and rooms are warm.
- **Intensity tracks ambient light.** Dim room → dim LEDs. Bright daylight → LEDs barely register, which is correct: the room is doing its own light during the day.
- **Maximum intensity is "noticed without dominating."** Atmospheric, not signage.
- **Rest state is not pure black.** At rest, the LEDs hold a barely-visible warm presence. Off-state is for power-off; rest-state is for "nothing playing right now."

Color sourcing:

- The felt orange in LED has a hardware-calibrated value to match the felt under good light. Digital-orange and LED-orange are different problems; they share a target, not an RGB value. Calibration finalized once LED hardware is selected.
- Album-derived color in LED uses the same source palette as the screen but renders with saturation and gamma adjustments specific to the LED color profile. The same album should *feel* the same on the stand as in the app, even if the absolute RGB differs.

The canvas:

- Each crate's LED strip is a 70-slot writeable canvas. The stand is a separate canvas at the stand's glow zone.
- LEDs are not status indicators. They are surfaces the system writes to using the same color vocabulary as the screen.
- Slot-marks fade overnight (see §6, Lighting Primitives). The fade is part of color rendering, not a separate animation.

### §2.5 Vetoes

- **No tan, brown, beige, terracotta, oat, or earth-warm cream palettes.** Warmth is the wordmark, the felt orange, and album art — not the UI's pigment. *(Implements framework veto.)*
- **No second structural accent.** The felt orange is the only system color. Other needs are solved through ink, weight, position, motion. *(Implements framework veto.)*
- **No semantic state colors.** No success-green, error-red, warning-amber as a system. State is communicated by text, position, presence, or motion. *(Implements: no celebratory milestones, no comparative metrics — the system speaks in language and motion, not in stoplight color.)*
- **No tinted UI on listening surfaces.** Album-derived color is atmosphere on backgrounds and edges only; chrome stays ink-on-paper.
- **No album-derived color in the archive.** The archive is paper/ink. *(Implements: two rooms, never blended.)*
- **No felt orange in listening surfaces.** Album art owns those moments. *(Implements: the orange owns identity moments, album art owns listening moments; they never share screens.)*
- **No pure black anywhere, including LED rest state.** Black reads as off; the brand is never off, just quiet.
- **No "brighter digital orange" substitute for the felt orange.** The orange is the felt. If the rendering can't match it, the rendering is the problem.

### §2.6 To revisit

- Final felt-orange value measured from the physical sample.
- Album-derived extraction algorithm (k-means? median cut? Vibrant.js? A custom approach tuned for vinyl-era cover photography?).
- LED hardware calibration once the strip is selected.
- Whether dark-mode felt-orange needs a separately-measured value, or whether one value works in both modes when surrounded by the right ink.
- Ambient-light curve for mode switching — how dim is "switch to dark," and what hysteresis avoids flicker at the threshold.
- The "no art" surface for missing album metadata — is it strictly paper/ink, or is there a quiet system identity that fills in?

---

## §3 Typography

**Status: in exploration.** Working defaults below. We'll refine after building reference experiences and seeing how the system reads in context.

### Decisions

The body type system uses three faces, each doing one job:

| Face | Job | Working pick (open-source) | Production candidate |
|---|---|---|---|
| Sans | UI chrome, labels, controls, secondary metadata | **Inter Tight** | Söhne (Klim) |
| Serif | Album titles, narrative prose, witness data, attention moments | **Source Serif 4** | Tiempos Text (Klim) |
| Mono | Matrix numbers, runout etchings, timings, pressing data | **JetBrains Mono** | Söhne Mono (Klim) |

The open-source picks let us ship and build today with no licensing friction. We re-evaluate against the Klim pairing once we have real screens and a real wordmark to balance against.

The wordmark is not in this table. It is its own thing, used once.

### Why three faces

The brief asks the body type to disappear in the presence of music and album art. A neutral sans alone can do that, but it can't carry the narrative and witness register the per-record archive depends on. A serif can carry the narrative, but at small UI sizes it reads editorial and wrong. And neither can render matrix numbers and side timings the way the archivist needs them to read — for that the system needs a true mono with tabular figures.

Three faces, one designer's logic running through them. The picks above were chosen as a *system* — proportions, x-height, and rhythm that work together — not as three independent best-of-class choices.

### Rules

- **Hierarchy comes from weight, size, and position. Not from color.** The system has no color of its own (§2); typography carries hierarchy on its own shoulders. This makes type structural, not decorative.

- **Sans is the default.** Use it unless there is a reason. Almost all UI is sans.

- **Serif is for attention.** Album titles. Per-record narrative. Witness data written as memory ("first played one Saturday in October 2019"). Anything where the user is being asked to *attend*, not to *do*. Italic is a real part of the system here — use it for temporal and observational language, not for emphasis.

- **Mono is for facts.** Matrix numbers, catalog numbers, runtimes, weights, gear chains, dates displayed as data rather than narrative. Tabular figures are required — numerics in lists must not jump as values update.

- **Two weights, not five.** Regular (400) and Medium (500) cover almost everything. Heavier weights pull toward the wordmark's territory. If a hierarchy needs more contrast than weight + size + position provides, the hierarchy is too complicated.

- **Sentence case everywhere.** Never Title Case, never ALL CAPS. Including eyebrow labels and section heads. Capitalize the first word and proper nouns; let everything else be lower.

- **The wordmark is the only retro letterform in the system.** No other type may borrow its character. Display sizes of the serif and the sans must remain quiet at scale; if a large heading is doing personality work, the system has drifted.

### Cross-surface mapping

- **Apps** — all three faces available, loaded as web fonts or bundled with the app binary. Use variable axes when available.
- **Print & packaging** — same three faces. Serif is the natural choice for liner-note-style content; sans for UI-like elements (track listings on a packaging back); mono for catalog data.
- **The room** — type rarely appears here. The room is light, not letters. If a hardware surface ever needs text (a future product, a small display), it inherits these picks.

### Vetoes

- No additional faces. The system is closed.
- No display or "personality" typefaces. Implements *the wordmark sings; everything else holds the quiet so the wordmark can*.
- No mid-century or geometric sans (Futura, Avenir, Eurostile). Implements *the wordmark is allowed to be retro; nothing else is*.
- No literary or editorial serifs (Caslon, Garamond, Bodoni). Pulls the brand toward hipster-nostalgia and away from the music.
- No system defaults (Helvetica, Arial, Times). Under-considered for a craft product.
- No weight below 400 for body text. No weight above 500 anywhere.

### To revisit after building

- Whether the serif feels right for the archive register, or whether it tips precious.
- Whether two weights is enough for the listening room's hierarchy.
- The display sizes of both faces against the actual wordmark, once we have it.
- Whether the open-source picks are close enough to the Klim candidates that the shift is invisible, or whether the difference is meaningful enough to upgrade earlier than planned.
- Whether the sans should be Inter Tight specifically or one of the newer alternatives (Geist, DM Sans) that may sit closer to Söhne.

---

## §4 Spacing & Rhythm

**Status: in exploration.** Working scale and initial rhythm rules; values to validate against real screens.

The system has no color of its own. Typography is restrained. Almost everything left to communicate hierarchy and meaning lives in space — how much, where, and with what cadence.

### §4.1 The spacing scale

A 4-pixel base unit. Multiples chosen to support tight UI internals, comfortable composition, and atmospheric room-scale gaps.

| Token | Px | Use |
|---|---|---|
| `space-1` | 4 | Tight component-internal (icon-to-text gap, inline pill padding) |
| `space-2` | 8 | Component-internal (input padding, button internal) |
| `space-3` | 12 | Between related elements (label-to-input, list row internals) |
| `space-4` | 16 | Base gap. Between unrelated elements in the same group. |
| `space-6` | 24 | Between groups within a section |
| `space-8` | 32 | Between sections |
| `space-12` | 48 | Between major regions (page header to content) |
| `space-16` | 64 | Atmospheric page-level breathing |
| `space-24` | 96 | Large compositional space; the listening room uses this often |

The scale is intentionally short. Nine stops cover everything. Half-step and arbitrary values are out — if a layout needs `13px` or `19px` to work, the layout is wrong, not the scale.

The scale is also intentionally linear, not geometric. 4× multiples produce a calmer rhythm than 1.5× or golden-ratio progressions. Saturday! is calm, not crescendo.

### §4.2 Two rhythmic registers

The same scale is used very differently in the two rooms. This is the system's main mechanism for making the listening room and the archive feel like different places without requiring different visual systems.

**Listening room rhythm.** Generous, atmospheric, sparse. Reaches for `space-12`, `space-16`, `space-24` routinely. Page padding is large (`space-12` minimum on small surfaces). Few elements per view; each gets room. The "one primary thing" principle is materialized in literal space — the primary thing has *more space around it* than anything else on screen.

**Archive room rhythm.** Denser, information-rich, considered. Reaches for `space-3`, `space-4`, `space-6` routinely within regions, while regions themselves are separated by the larger end of the scale. Per-record pages pack pressing details, narrative, witness data, and play history without feeling cluttered, because density inside a region is paired with generous separation between regions.

The rule: page-level spacing is similar between rooms; within-region density differs. The listening room is mostly negative space with one thing in it. The archive is mostly positive space with regions of density inside larger gaps.

### §4.3 Typographic rhythm

The serif and the sans set different cadences. The system honors them.

- **Serif body** — line-height `1.65`, measure `60–65ch`. Long-form reading rhythm. Per-record narrative, witness passages.
- **Sans body** — line-height `1.5`, measure `70–80ch`. UI prose, descriptive copy, helper text.
- **Sans label / metadata** — line-height `1.3–1.4`. Compact, scanning rhythm.
- **Mono technical data** — line-height `1.4`. Tabular alignment matters more than reading cadence; sit comfortable but tight.

Vertical rhythm between elements:
- Paragraphs separated by `space-4`.
- Sub-section breaks separated by `space-6` to `space-8`.
- Major region breaks separated by `space-12` to `space-16`.

Combined with the two weights from §3 and the type scale, almost all hierarchy in Saturday! is built from three primitives: weight, size, and space. The combinations are simple and the constraints are visible. Hierarchy is structural, not decorative.

### §4.4 Grid and surface

Different surfaces use different grids; all share the spacing scale.

- **Mobile (phone)** — single column. Page margins `space-6` (24px) by default; can collapse to `space-4` for dense archive content. Content width fills viewport minus margins.
- **Tablet** — single column at narrower widths; two-column above ~720px where content suits it. Margins `space-8` (32px).
- **Desktop** — content is constrained for reading. The listening room caps at ~720px; the archive can use up to ~1100px for two-column compositions. Margins `space-12` (48px) or more.
- **Print** — page margins follow print conventions (minimum ~19mm / 0.75" on standard letter). Within-page spacing uses the same scale.
- **The room (LED)** — has no grid. The crate's slot positions are the grid; the stand has a single canvas. Spatial decisions in lighting are about *which* slots glow and where the stand's glow zone sits, not how much padding around them.

Page-level gutters and margins are conservative on small surfaces and more generous on large ones. The listening room can be generous on every surface; the archive denser.

### §4.5 Constraints

- **No half-step values.** `13px`, `19px`, `25px` are out. Use the scale or change the scale.
- **No arbitrary line-height.** Use the typographic rhythm values.
- **No grid-less layouts.** Even the listening room — which often shows one big thing — sits on a structure. A composition can feel spontaneous; the underlying rhythm shouldn't be.
- **Minimum touch target 44pt (iOS) / 48dp (Android).** Implicit from platform conventions; restated because the aesthetic preference for small affordances must never override this.

### §4.6 Vetoes

- **No dense lists with tight spacing in the listening room.** Density there reads as catalog-forward (framework veto). The listening room is in-the-moment, not browsing.
- **No spacing-as-decoration.** Whitespace must do compositional work (separating, grouping, elevating the primary). Space added "for breathing" without a reason is wallpaper.
- **No spacing inconsistency for emphasis.** A larger gap "to draw attention" is decoration. Emphasis comes from position and weight; gaps come from the scale.

### §4.7 To revisit

- Whether the scale needs a `space-32` (128px) for hero moments in the listening room, or whether `space-24` is sufficient.
- Mobile margin values once we build a real now-playing card and feel them at thumb distance.
- Whether the desktop archive needs a finer multi-column grid (12-col, 16-col) for complex per-record pages, or whether section-by-section layouts suffice.
- The specific transition rules between rooms — when navigating listening room → archive, does spacing change smoothly, or does the surface snap to a new rhythm? (Likely belongs to §5 Motion.)

---

## §5 Motion

**Status: in exploration.** Principles, vocabulary, and working curve / duration ranges below. Specific values to validate against real surfaces.

Motion is the most important non-color tool the system has for communicating state. Because the system has no color of its own and the typography is restrained, *change* has to be expressed through some other channel — and motion carries that weight on every surface, from screen to crate LED.

The framework's stance on motion is unusual and worth restating: *ambient surfaces communicate state, presence, and moments — not continuous data. The unit of communication is a change the user notices, not a value the user reads.* That single sentence rules out most of what a contemporary app's motion vocabulary contains.

### §5.1 Principles

- **Motion communicates a state change. Nothing continuous.** No spinners, no progress bars, no thinking animations, no audio-reactive visuals, no continuously updating values. Motion happens once per change; the rest of the time, the system is still.

- **Single-gesture, never iterative.** A pulse is one beat, not a heartbeat. A fade is one journey, not a breath. If a gesture wants to repeat, the system is escalating, which is not allowed.

- **User actions are sovereign over the system's motion.** Any user action interrupts any in-progress system gesture, instantly, with no completion animation, no reverse, no spring-back. The system never animates resistance.

- **The system never animates an argument.** No "are you sure," no shake/wiggle on undo, no bounce on dismissal. When the user dismisses something, the system recedes; it does not re-present, re-confirm, or re-explain.

- **Walking away is data.** No return-attention motion. Nothing pulses harder, escalates, or "comes back" because the user didn't respond. An invitation ignored simply was, and then wasn't.

- **Loading is a held state, not an animated state.** When the system is fetching or computing, the surface holds a skeleton in paper-tones. The arriving content uses the *arrive* gesture once ready. No spinner. No "working on it." The substrate is patient.

- **Motion is the same gesture across surfaces.** A pulse is a pulse whether it's an opacity transition on screen or an LED briefly brightening. The implementation differs; the gesture's identity does not.

### §5.2 The motion vocabulary

Seven gestures cover everything the system does. Each has a purpose, a duration region, and a curve.

| Gesture | Purpose | Duration | Curve |
|---|---|---|---|
| `arrive` | Something becomes present (content lands, stand glows, slot marks) | Quick to Standard | ease-out |
| `recede` | Something stops being relevant (dismissal, invitation expires) | Standard to Slow | ease-out |
| `pulse` | Single-gesture "I'm here" or invitation. Up to peak, back to rest. | Slow | symmetric ease-in-out |
| `settle` | Layout reflow or content updating without urgency | Quick to Standard | ease-in-out |
| `blend` | Color or state transitions (stand color changing between albums) | Standard to Slow | ease-in-out |
| `override` | The user took an action that supersedes a system gesture | Instant | none |
| `hold` | Stillness. The system at rest is not a gesture being executed — it's a state being held. | — | — |

`hold` is named because it is the system's most common state. Most of the time, nothing should be moving. Calm is a positive state, not the absence of motion.

### §5.3 Easing curves

Three named curves. The bias is toward decelerating motion — gestures arrive confidently and settle. Acceleration-into-motion (ease-in alone) is rare; it reads as urgent or hasty, neither of which is Saturday!.

| Curve | cubic-bezier | Use |
|---|---|---|
| `ease-arrive` | `(0.16, 1, 0.3, 1)` | Strong deceleration. Arrivals, content landing, stand glow becoming present. |
| `ease-recede` | `(0.7, 0, 0.84, 0)` | Soft start, exit. Recessions, dismissals, the overnight fade. |
| `ease-blend` | `(0.45, 0, 0.55, 1)` | Symmetric, gentle. Pulses, blends, settles between two stable states. |

Linear interpolation is permitted only when the gesture's *nature* is constant motion — the overnight fade across hours is effectively linear at any human scale. Otherwise, use a curve.

### §5.4 Duration regions

Five regions. Components pick a value within the region appropriate to the gesture, not arbitrary milliseconds.

| Region | Range | Use |
|---|---|---|
| `instant` | 0 ms | User-sovereign overrides. Direct cuts. No animation. |
| `quick` | 120–200 ms | Tight UI feedback (focus state, hover, tap). |
| `standard` | 250–400 ms | Most arrivals, recessions, settles, content transitions. |
| `slow` | 600–1500 ms | Pulses, atmospheric blends, the stand changing color between records. |
| `ambient` | minutes to hours | The overnight fade. State persists, then quietly resolves. Unique to lighting. |

Two specific durations to anchor the system:
- The system's signature **pulse** is approximately **1500 ms** — peak around 700 ms, return to rest. Slow enough that it reads as breath, not heartbeat.
- The **overnight fade** of crate slot-marks runs from listening end to the next morning. Hours of duration, but a single ease-recede gesture, not a series of steps.

### §5.5 Cross-surface translation

The same gestures, expressed in different media.

**Apps (screen).** Motion is CSS transitions, native platform animations, or compositor-driven. The vocabulary maps directly to property changes — opacity, transform, color interpolation. The system avoids motion that depends on physics simulations (springs, friction); calm is best served by clean curves with named values.

**The room (LED).** Motion is intensity over time. An `arrive` is a brightness ramp from rest to peak using `ease-arrive`. A `pulse` is a symmetric brightness curve. A `blend` is a color interpolation in the LED's color space (not in sRGB — see §2.4). LEDs do not animate position; their canvas is fixed.

**Haptics (mobile).** Motion sometimes pairs with a single, brief haptic — the tactile equivalent of an arrival or override confirmation. Rare. See §8.

**Print & packaging.** Static. No motion. The brand's restraint is its only "animation" in print.

The key cross-surface property: **gestures are identifiable across surfaces**. A user who feels a slot-mark pulse on the crate and an invitation arrive on their phone should sense them as the same kind of system move, not two different products talking.

### §5.6 Transitions between rooms

The listening room and the archive are different places. Navigating between them is a state change, not a screen change.

The transition is a brief cross-fade — `standard` duration, `ease-blend` curve. No slide, no scale, no parallax, no cinematic flourish. The user is crossing a threshold; the rooms themselves don't perform.

This is deliberate. Streaming-app transitions sell themselves — the design draws attention to the transition. Saturday!'s rooms are *places*; entering them is the act, not the show.

### §5.7 Vetoes

- **No looping animations.** Exception: the ambient overnight fade, which loops only in the sense that each evening is a new fade. Within an evening, gestures happen once.
- **No spring or bounce effects.** Implements: *the controlling host defends them*. Saturday!'s motion never argues, recoils, or recoils-back.
- **No "completion" or "celebration" motion.** No checkmark animations, no confetti, no success ripples. State changes are quiet acknowledgments at most.
- **No audio-reactive visuals.** Waveforms, spectrum analyzers, beat-sync VFX — these are streaming-app aesthetics. The room visualizes the *shape of the evening* (§6), not the audio signal.
- **No motion that survives a user override.** If the user acts, every in-progress system gesture cuts immediately.
- **No spinners, loaders, or progress indicators.** Loading is held space (paper-tone skeleton); arrival is the *arrive* gesture.
- **No motion that demands a response.** A pulse that repeats until tapped is a notification. Saturday! does not have notifications.
- **No "missed it" replay motion.** If a user didn't see an invitation, the system does not re-present it on next open or "highlight" it.

### §5.8 Accessibility

The system respects `prefers-reduced-motion` on all surfaces that support it.

- **State-change motion is preserved.** An arrival is still an arrival; the property still changes. But the curve becomes near-instant, with only enough duration to avoid visual abruptness (~80–120 ms).
- **Pulses become a one-time appearance, not a brightness curve.** The invitation still arrives; it doesn't breathe.
- **Blends become cross-cuts.** No interpolation between colors; the new color replaces the old in a single quick step.
- **The overnight fade remains.** It runs over hours and is not a vestibular concern.

### §5.9 To revisit

- Specific curve values tested on real screens — the cubic-beziers above are working defaults.
- LED-specific timing curves once hardware is selected. The screen-to-LED translation may need per-gesture tuning.
- Whether room transitions ever differ — should entering the archive from the listening room feel different than the reverse? Probably no, but worth checking once both rooms are built.
- The exact pulse duration. 1500 ms is a starting point; could be 1200 or 1800.
- Whether haptics belong here (paired with motion) or fully self-contained in §8.

---

## §6 Lighting Primitives

**Status: in exploration.** Gestures and rules below; hardware values and edge cases to validate.

Saturday!'s most distinctive surface is the room itself. The lighting layer is not an output channel for a screen-based product; it is a peer surface with its own vocabulary, behaving according to the same principles as everything else.

The framework's framing is the source: *the room is the visualization. The evening writes itself on the furniture.* This section makes that framing usable.

### §6.1 The room as canvas

Two intelligent canvases work in concert:

- **The now-playing stand** — a single canvas at the stand's glow zone. Renders the present moment.
- **The crates** — each crate's LED strip is a 70-slot writeable canvas. Renders the accumulated history of the evening, slot by slot.

A listener may have one crate or many. The system composes whatever crates are present on the local network into a single room canvas. The relationship between crates is spatial (where they sit in the room) and conceptual (each is a chapter of the evening's shape).

The room is **event-driven, not signal-driven**. The lighting responds to RFID events, ambient light, and pattern observations — never to audio signal. The room does not visualize the music. The room visualizes *the evening of music*.

### §6.2 The lighting gestures

Each gesture has a trigger, a visual behavior, a color source, and a duration. All map to motion vocabulary from §5 and color rules from §2.

**Slot mark.** When a record leaves a slot and arrives at the stand, the source slot illuminates with the record's album-derived color. The mark persists at moderate intensity for the rest of the evening. Once a slot is marked tonight, it stays marked until the overnight fade.

- Motion: `arrive` (§5). Color: album-derived (§2.3). Duration: persistent through the evening; fades overnight.

**Stand glow.** When a record is on the stand, the stand canvas glows with the album-derived color. Intensity sits at the system's "noticed without dominating" maximum, modulated by ambient light (§2.4).

- Motion: `arrive` on placement; `hold` while present. Color: album-derived. Duration: as long as the record is on the stand.

**Stand blend.** When one record is removed and another is placed within a short window, the stand color transitions between the two albums via the `blend` gesture (§5). When a record is removed and no new record arrives, the stand lingers at the previous album's color, then `recede`s to rest-state over the next 30–60 seconds. The lingering fade is deliberate — the just-played record is still in the air, gradually clearing.

- Motion: `blend` (album-to-album) or `recede` (album-to-rest). Duration: blend ~1200 ms; lingering recede ~30–60 s.

**Crate invitation pulse.** When the system notices a crate often follows the current evening's pattern, that crate pulses once — a single-beat brightness curve across the full strip or a subset of likely-relevant slots. Color: a quiet album-derived color from a record the system would suggest, or rest-warm if the system is gesturing at the crate as a whole rather than at specific records.

- Motion: `pulse` (§5). Once, never escalating, never repeating. Detail in §6.6.

**Evening fade.** Some hours after listening has ended and ambient conditions suggest the listener has left or gone to sleep, the slot marks begin to fade. The fade is `ease-recede` over hours, completing before approximate morning. By dawn the room is at rest-state; the next evening writes on a clean canvas. Detail in §6.5.

- Motion: `recede` (§5). Duration: hours.

**Rest state.** When nothing is playing and no listener is present, the canvases hold a barely-visible warm presence. Not off (off is power-off). Not pure black (vetoed). Not informational. The room is *quiet*, not *empty*.

- Color: warm-neutral, anchored to ~2700K. Intensity: ~5–10% of peak, modulated by ambient light.
- Uniform across stand and crates. Identity belongs to the records, not the surfaces.

### §6.3 Two visual layers

The room renders two layers simultaneously and they never conflict, because they occupy different canvases:

- **The present moment** — the stand's glow, carrying the current album's color.
- **The accumulated history** — the crate slot marks, carrying the colors of records played tonight.

The listener reads both at a glance: where the evening is now (stand), where the evening has been (crates). The stand color and one of the crate slot-marks always match — that mark is the record currently playing, and the visual line between them tells the listener where the music came from.

### §6.4 The shape of the evening

Individual lighting events compose into a meaningful artifact: the shape of the evening, made physical.

Two rules govern composition:

- **Rhythm, not time.** Every record gets an equal mark. A 17-minute side and a 45-minute side and a single 7-inch get the same kind of mark — "this record was part of the evening." The lights are state-language, not duration-language. Saturday! is not quantifying the evening; it is acknowledging it.
- **Evening as a unit.** Marks accumulate within a single evening and resolve overnight. Each night writes its own shape, complete in itself, and is allowed to fade by morning. The system does not save the shape in light; the witness lives in the per-record archive instead.

### §6.5 The morning reset

The overnight fade is the room's most distinctive gesture and the one that most clearly distinguishes Saturday! from data-keeping systems.

When listening has clearly ended — a sustained quiet period, late ambient light, the listener absent — the system begins fading the slot marks. The fade uses `ease-recede` across hours, completing before approximate morning. By the time the listener returns to the room, the canvas is clean.

This is intentional. The evening was a unit; it is complete. The system kept witness; the witness lives in the per-record archive (where it persists), not in the room (where it doesn't need to). The room is for the *current* evening. The archive is for all evenings.

If a listener wants to see the shape of past evenings, the archive can render that visualization. The room never tries to be a memorial.

### §6.6 Crate-as-invitation, in detail

The crate invitation pulse is the framework's most beautiful expression of the *invitations not notifications* principle and deserves explicit specification.

**Trigger.** Pattern observation. The system has noticed that this crate often follows the current evening's shape — same time of day, same starting record, same posture (chair vs. room). The signal is statistical observation, not certainty.

**Behavior.** A single pulse across the full strip, or a subset of slots the system has confidence about. Color: a quiet derived-color from one of the records the system would suggest, or rest-warm if the system is gesturing at the crate as a whole.

**No follow-up.** If the listener notices and engages, behavior follows naturally. If they don't notice, nothing happens. No re-pulse, no escalating brightness, no marker that the invitation occurred. The system was paying attention; the invitation was given; the rest is the user's evening.

**Frequency.** Rare. An invitation that happens every evening is a notification. The trigger threshold must be conservative enough that the gesture remains distinctive.

### §6.7 Cross-surface coupling with the app

The room and the app are not duplicate channels. They are two views of the same listening, expressing complementary information.

- **Stand glow + app now-playing card.** Both show the current album's color and the listening present-tense. Stand from across the room; app at thumb distance.
- **Slot marks + app session view.** Both express "the evening so far" — slot marks as a spatial pattern in the room, session view as a composed list in the app.
- **Crate invitation pulse + app session suggestion.** Both invite. The room invites the crate-as-a-whole; the app can elaborate (which records, why now). Neither demands a response.

The rule: the room and the app never disagree. When they show the same fact, the encoding is appropriate to the surface — light for ambient awareness, pixels for active engagement. Neither is a redundant copy.

### §6.8 No-art and unknown cases

When a record has no available cover art or release-level color data, the lighting cannot render an album-derived color honestly.

The system's response is to use a quiet warm-neutral mark or glow — the same warm-neutral as the rest state, at noticeable intensity. This communicates "this record was played" without inventing a color identity.

The framework principle holds: the system never fakes what it doesn't know. A neutral mark is honest; a synthesized color would be dishonest.

### §6.9 Hardware implications

Design decisions above constrain hardware specification.

- **Per-slot LED addressability.** Each crate slot must be independently addressable. 70 slots per crate (standard). Color depth sufficient for subtle album-derived rendering (24-bit RGB minimum).
- **Color rendering toward warm room-light.** LEDs must render toward a ~2700K reference. Consider RGB+W (warm white channel) for accurate rest-state warmth and overall room compatibility — pure RGB cannot produce true warm white at low intensity without color shift.
- **Wide intensity range.** Convincing dim to ~5% of peak for rest, ~20–30% for marks, without color shift. PWM frequency high enough to avoid visible flicker at low duty cycles.
- **Ambient light sensor (recommended).** Allows intensity to track room brightness. Without it, the system falls back to time-of-day inference and platform-level light data, which is less reliable.
- **Crate design for positional legibility.** The listener must be able to read which slot is glowing and connect it to the record at that position. Crates designed to be seen as much as used.
- **Local network connectivity.** Crates and stand communicate locally. A new crate joins the canvas without setup beyond physical connection.

### §6.10 Vetoes

- **No status indicators.** No power LEDs, sync LEDs, battery indicators, error blinks. Saturday! has no hardware status language; problems surface (if at all) in the app.
- **No audio-reactive lighting.** No spectrum analyzers, beat-sync visuals, waveforms. The room responds to events, not signals.
- **No notification pulses.** Repeating, escalating, attention-demanding patterns are out. *(Implements: invitations not notifications.)*
- **No "active listening" cue.** No light that says "I am observing." The room observes silently; the act is not announced.
- **No celebratory or milestone lighting.** No "1000th play" pulse, no "complete collection" sweep. *(Implements: no celebratory milestones.)*
- **No setup-mode lighting that overrides listening.** Hardware setup is silent or relies on the app, not on commandeering the canvas.
- **No demanding patterns.** Anything that requires the user to notice or respond is out.
- **No clock or duration display in light.** Time is not a Saturday! quantity. Lights stay in state-language.

### §6.11 To revisit

- The exact color for the "no art" mark and rest state. Working assumption: warm-neutral at ~2700K, with intensity distinguishing rest from mark.
- The threshold and frequency cap on crate-invitation pulses. How often is "too often"?
- Multi-listener and multi-room scenarios. If a household has overlapping sessions, how does the room handle competing evenings?
- The "wake" behavior in the morning. Is there a "good morning" gesture, or does the room just be ready when needed? Strong intuition: no morning gesture. The room is silent until invited.
- The exact stand-fade duration after record removal. 30–60 s is a working range; needs validation in real listening.
- Whether crates can be visually identified by light (e.g., the jazz crate has a different rest-state warmth than the rock crate). Strong intuition: no. Rest state is uniform; identity belongs to records.
- The overnight fade's start trigger. Inactivity, time-of-day, ambient darkness change — likely a combination.

---

## §7 Sound & Audio

**Status: exploratory.** *To be written as a brief exploration. The framework implies a near-silent product — invitations not notifications, walking away is data, the music is the sound — but it's worth naming what sound could legitimately do in Saturday! before deciding whether it does anything at all.*

---

## §8 Haptics

*To be written.*

---

## §9 Iconography & Marks

*To be written.*

---

## §10 Voice & Copy

**Status: settled in posture; specific vocabulary in exploration.** The rules are clear; the per-surface vocabulary needs validation in real screens.

The voice is the brand's most pervasive surface. Almost every screen contains words; almost every word is a choice. The framework's posture toward the user — *thoughtful host, never controlling host* — has to be encoded in how the system speaks, or it won't carry across the surfaces.

### §10.1 The voice

Saturday! speaks rarely. When it speaks, it is **specific, observational, restrained, and warm without performance.**

- **Specific over generic.** "Coltrane crate, often follows what's playing now." Not "We thought you might like this."
- **Observational over evaluative.** "Twenty-three plays, most after dark." Not "Your favorite record."
- **Restrained over enthusiastic.** Statements end. They do not announce themselves with enthusiasm or invite further engagement.
- **Warm without performance.** Warmth shows in attention to detail, not in friendliness markers. No "hi," no "let's," no "we're here for you."
- **Reverent toward the music; understated about itself.** Album titles, artist names, personnel are honored exactly. The system's own contribution is described as little as possible.

The reference: a record-shop owner who already knows what you like and doesn't have to tell you about it. Or a museum docent who answers when asked and is otherwise silent.

### §10.2 Address

**The system rarely refers to itself.** When unavoidable, it speaks in the third person — *the room, the stand, the system* — not in first person. The word *I* does not appear. *We* is reserved for genuine brand-to-customer communication (a receipt, a setup completion message) and even then is used sparingly. Never in listening surfaces.

Preferred forms, in order of preference:
- *Pure observation, no subject:* "Often followed by Coltrane."
- *Surface as subject:* "The room noticed this crate often follows."
- *Third-person system reference:* "The system has noticed..." Used rarely; the system should not keep announcing itself.

**The system rarely addresses the user directly.** Second-person (*you*) is sparse; implied subject is preferred. The framework's *the user's actions are sovereign* posture is undermined by constantly speaking to the user.

Preferred forms:
- *Implied subject:* "Three records into the evening." Not "You've played three records."
- *Possessive only when necessary:* "The collection" when context implies ownership, rather than "Your collection."
- *Direct address:* reserved for moments where the user is genuinely being asked something. Even then, no greetings, no encouragement.

The word *user* does not appear in user-facing copy. The user is the listener, the collector, the person — or no subject at all.

### §10.3 The witness register

The witness register is Saturday!'s unique copywriting mode — used on per-record pages, in narrative observations, and anywhere the system records the relationship between a record and a listener.

Witness writing is **temporal, specific, and observational.** It is the language of memory, not measurement.

- **Time as memory, not as timestamp.** "One quiet Saturday in October 2019" is preferred to "October 12, 2019." When precision is required (legal, archival), give it plainly elsewhere on the page.
- **Numbers serve witness when they carry meaning.** "Twenty-three plays" reads as observation. "23 plays" reads as data. The mono typeface (§3) is reserved for tabular data; witness narrative uses the serif and spells numbers when they sit naturally in the prose. Numbers stay numeric when they're large or technical.
- **"Most" and "often" do work.** They're observational without being absolute.
- **No comparisons.** Witness narrative never compares this record to others, this listener to others, or this evening to others. *Specificity deepens; comparison flattens.*
- **Italic for temporal observations.** Per §3, italic in serif body carries witness-register temporal language: *one quiet Saturday*, *first heard*, *most often*. Used judiciously.

Example witness paragraph:

> First heard *one quiet Saturday* in October 2019. Twenty-three plays so far, most after dark. The record returned to when the room needs centering.

Three sentences. Temporal anchor. Witness observation. Felt meaning. No metrics, no comparisons, no calls to action.

### §10.4 Vocabulary

Some words from the streaming-app universe are not used. Each has a Saturday! equivalent or is simply absent.

| Streaming-app word | Saturday! equivalent |
|---|---|
| Queue | Session (composed) or nothing — Saturday! does not passively queue |
| Playlist | Session, or no equivalent — no algorithmic playlists |
| Library | The collection, or the archive |
| Recommended for you | (nothing — no algorithmic recommendation) |
| Discover | (no dedicated surface — discovery happens through the archive's shape view or via invitations) |
| Trending / Popular | (nothing — no comparative metrics) |
| For you | (nothing) |
| More like this | (nothing) |
| Top tracks | (nothing — tracks are not ranked) |
| Skip / Next | (no concept — the side plays through) |
| Like / Heart / Star | (nothing — no rating system) |
| Add to library | "Into the collection" — rarely surfaced |
| Save / Bookmark | "Noted," or absent |
| Listening history | The per-record archive, or the play log |
| Now playing | "On the stand" is often more honest; "now playing" is fine but generic |

Words and phrases honored exactly:
- **Album titles**, as released. Italic in serif body.
- **Artist names**, as credited.
- **Personnel and credits**, as credited.
- **Side and track designations**, matching the actual sleeve (*Side A* vs. *Side One* — both valid depending on the pressing).
- **Pressing technical detail**, factually rendered in mono.

### §10.5 Tone across surfaces

**Empty states.** The room is quiet when nothing is playing. The app's listening room, when nothing is on the stand, is a single short line placing the listener in the moment — not a call to action.
- *"The stand is empty."* — not *"Start listening!"*
- *"The archive begins with the first record."* — not *"Add your first album!"*

**Invitations.** A single sentence, observational, no ask. Reflects the room's invitation pulse (§6.6).
- *"Coltrane crate, often follows what's playing now."*
- *"Sunday morning, the usual set is on the third shelf."*

No *Want to...*. No *Try...*. No exclamation.

**Action confirmations.** None. The action happens. The relevant surface reflects the new state. No banner, no toast, no confirmation modal.

**Errors.** Plain, factual, present tense. No apology, no exclamation, no *oops*.
- *"Stand isn't responding."*
- *"Cover art unavailable — slot marked in warm neutral."* (rare; this is so factual it likely never surfaces in copy at all)

The system handles edges quietly. Most errors are absorbed by the substrate (§2.3 no-art, §6.8) and never surfaced.

**Setup.** First-time use is short and undemonstrative. The framework's *the interface arrives with a point of view* applies — defaults are chosen, configuration is minimal, the system is ready when the user is.
- *"Plug in the stand. Place a record."*
- *"Connect the crate. Records will identify themselves."*

No *Welcome to Saturday!*. No *Let's get started*. No tutorial sequences. The product begins the moment a record is played.

**Witness narrative.** See §10.3.

**Sessions.** User-named when the user names them; system-described otherwise.
- System-described: *"Tuesday evening, three records, ending in Coltrane."*
- User-named: *"Late October, hosting."*
- The user's name takes precedence when both exist.

### §10.6 Music metadata copy

Music is honored, not standardized.

- **Album titles**: exactly as released. *Bitches Brew*, not *Bitches' Brew*; *A Love Supreme*, not *A Love Supreme!*. Diacritics, capitalization, and punctuation as on the cover. Italic in body serif.
- **Artist names**: as credited. No *feat.* abbreviations unless they appear on the cover. No reformatting.
- **Side designations**: as on the record. *Side A* or *Side One* — match the pressing.
- **Catalog numbers**: rendered in mono, as printed. *BST 84003*, *SD 1419*.
- **Matrix and runout**: rendered in mono, exactly as etched. *RVG STEREO A-1*, *SD1-1419-A 1A*.

The rule: when in doubt, defer to how the record presents itself. The album's typography is not Saturday!'s typography; the album is honored within Saturday!'s.

### §10.7 Banned patterns

Out across all surfaces.

- **Greetings of any kind.** No *Hi*, *Hello*, *Welcome*, *Welcome back*.
- **Encouragement or praise.** No *Great choice*, *Nice pick*, *You're on a roll*.
- **Apologies.** No *Sorry*, *Oops*, *Something went wrong*.
- **Confidence indicators around suggestions.** No *We think...*, *Probably...*, *Looks like...*, *Based on your listening...*.
- **Urgency or scarcity.** No *Don't miss*, *Hurry*, *Limited*, *Last chance*.
- **Generic calls to action.** No *Click here*, *Tap to*, *Learn more* without a specific noun.
- **Self-congratulation.** No *smart matching*, *intelligent suggestions*, *powered by...*. The system never describes its own cleverness.
- **Comparative language.** No *Most-played*, *Top*, *Trending*, *More popular than...*.
- **Numeric ratings.** No five-star, no *8.5/10*, no percentage matches.
- **Emoji.** Anywhere. Including in invitations, witness data, sessions, errors.
- **Exclamation points.** Reserved for the wordmark itself, which is *Saturday!*. Nowhere else. Hard rule — the wordmark earns the exclamation; nothing else does.
- **ALL CAPS for emphasis.** Per typography §3. Caps appear only in technical data where the source uses them (matrix numbers, catalog labels).
- **Title Case for headings or labels.** Per typography §3. Sentence case throughout.
- **Tutorial imperatives.** No *Now, let's...*, *Here's how to...*, *First, you'll want to...*.
- **Feedback solicitation.** No *Rate this*, *How are we doing?*, *Tell us what you think*.
- **Marketing voice.** No *Featured*, *Hand-picked*, *Curated for you*, *Just for you*.

### §10.8 Cross-surface considerations

The voice is consistent across surfaces; the *frequency* of speaking varies.

- **The room (LED).** Does not use words. State-language only (§6). Voice & copy do not appear.
- **The app.** Most copy lives here. The listening room is sparse; the archive is denser (per-record pages, sessions, narrative).
- **Print & packaging.** The voice in print can be longer-form (an insert card, liner notes for a printed session). Same posture, same vocabulary; more room to develop the witness register.
- **Push notifications.** Reserved for session-enriching signals only: state changes (record placed on the stand, low battery, hardware needs attention), session courtesies (side-flip coming, next record ready), and listener-configured reminders (a morning briefing the listener set up). Never used for promotion, re-engagement, or algorithmic suggestion. Listeners opt in; categories are granular; pushes are quiet by default and follow the §6.6 invitation rules (single beat, no badge, no escalation, no follow-up if ignored). The voice in any necessary system email (receipt, password reset) is plain and factual.

### §10.9 To revisit

- Specific empty-state copy for every surface — the examples above are starting points.
- Setup flow copy in full once the flow exists.
- Whether sessions get system-generated default names ("Tuesday evening, three records") or stay un-named until the user names them.
- Edge cases in error copy — what happens when a record is on the stand but the system cannot identify it?
- The voice for administrative communications (account, payment, support) — likely the same posture, but conventional language by necessity.
- Whether the witness register has formal sub-modes (temporal observation, felt meaning, pressing provenance) or whether one register handles all narrative.

---

## §11 Surface Decisions

**Status: in exploration.** Integrates decisions across foundations and resolves open questions surfaced by reference experiences.

This section is a tool, not a set of new rules. Given a thing to express, where should it live, what foundation primitive should carry it, and what does its absence teach? The framework already answers these questions through its principles; this section makes the answers operational.

### §11.1 The house metaphor

Saturday! is a house with two main rooms. The architecture is real, not a UI metaphor borrowed for convenience.

- **The listening room** — the default front door. Now-tense, opinionated, present. Where the listener arrives.
- **The archive** — a destination. Past-tense, dense, considered. Where the listener goes on purpose.

The two rooms are first-class peers. Neither is a tab inside the other. The listener moves between them by gesture, not by tab-switching.

**Navigation:**

- The rooms have spatial relationship. The archive sits *to the left* of the listening room. Horizontal swipe moves between them.
- A quiet eyebrow at the top of each page names where the listener is — *Listening*, *Archive*. This is wayfinding, not branding.
- Per-record pages are destinations *inside* the archive. Entering one is a step deeper, not a step sideways.
- Sessions belong primarily to the listening room when they are *now* (being composed, being played), and to the archive when they are *past* (a record of an evening).

**Settings is not a room.** It is a utility sheet that overlays the current room when invoked. Reached by a quiet affordance (a tap on a brand mark in a corner, a pull-down from the top — exact gesture to be determined). The settings sheet dismisses by gesture; it does not have its own navigation path. The listener is in a room, and the sheet is in front of it briefly.

The **LED room** (crates, stand) is a peer surface — not navigated via the app at all. It is always present; the app references it implicitly through atmospheric color and witness data.

### §11.2 Pattern-to-primitive map

Given a thing to express, the system uses one primitive — not several.

| Thing to express | Carried by | Reference |
|---|---|---|
| Hierarchy | Weight + size + position | §3, §4 |
| Identity | Wordmark, felt orange | §2.2 |
| Presence (here, now) | Album-derived color, stand glow | §2.3, §6.2 |
| Change of state | Motion (`arrive`, `recede`, `blend`) | §5 |
| Accumulated history | Slot marks, per-record archive | §6.2, §10.3 |
| Loading | Held space (paper-tone skeleton) | §5.1 |
| Error | Factual sentence | §10.5 |
| Witness | Serif narrative, italic for temporal | §3, §10.3 |
| Facts (matrix, timing, gear) | Mono | §3 |
| Invitation | Single pulse, optional one-line copy | §5.2, §6.6, §10.5 |
| Where the listener is | Eyebrow label | §11.1 |

**Things the system does not express:**

| Thing | Why |
|---|---|
| Confirmation | User actions are sovereign (§5.1) |
| Encouragement | Not the voice (§10.7) |
| Comparative ranking | Specificity over comparison (§2.5, §10) |
| Continuous progress | Motion is state-change only (§5.1) |
| System status | Never via lights or labels (§6.10) |
| "For you" feeds | Not in the architecture (§10.4) |

### §11.3 Where content lives

| Content type | Lives in | Appears in |
|---|---|---|
| Now playing | The listening room | Listening room screen; the stand |
| Album cover thumbnail | Wherever it identifies a record | Per-record pages, session views; never as derived color in archive |
| Per-record narrative (witness) | Archive (per-record page) | The per-record page only |
| Pressing details | Archive (per-record page) | The per-record page; possibly print/packaging |
| Care log | Archive (per-record page) | The per-record page only |
| Plays / play log | Archive (per-record page) | The per-record page only; never as a dashboard |
| Sessions in progress | Listening room | The listening room app; the room itself in light |
| Past sessions | Archive | Archive (sub-area, to be designed) |
| The shape of the collection | Archive home | The archive home screen |
| Hidden patterns | Archive | Archive home (collection-wide) + per-record pages (record-specific) |
| Invitations | Listening room | Listening room screen; the room itself (crate pulse) |
| Settings | Utility sheet | Overlaid on either room |

### §11.4 The drift-catcher checklist

A short audit any screen passes through before it ships. Each item maps to a vetoed pattern in earlier sections.

- Is there a *Now playing* header? Cut it — the screen is already in the listening room and the title carries it.
- Is there an exclamation point not in the wordmark? Cut it.
- Is there a chevron suggesting *more*? Either show the content inline or cut the affordance.
- Is there a toggle switch? Replace with stateful text (*off*, *local only*).
- Is there a loading spinner? Replace with held space.
- Is there a "for you" surface? Cut.
- Is there a rating or star? Cut.
- Is there a comparative metric? Cut.
- Is there an emoji? Cut.
- Is there a confirm-before-acting dialog? Cut — the user is sovereign.
- Is there a "welcome back" greeting? Cut.
- Is there a progress bar on anything? Cut. Saturday! is rhythm, not time.
- Is there a "we noticed" announcement of the system's cleverness? Cut.

If a screen passes all of these, it has the *negative space* the brand requires. The presence of any of these signals drift in progress.

### §11.5 Witness as co-authored

The per-record archive page raised the question: who writes the witness data? **Both the system and the user.**

- The system writes *observations*: first played, total plays, recency, patterns, acquisition date if from a structured source. These appear in the witness register's voice — temporal, observational, no comparison.
- The user writes *notes*: their reflections, memories, why this record matters. Same register; same voice; user writing is in serif body and follows the witness register's conventions.
- The two are not visually separated by author. The page is co-authored; the witness paragraph is a single stream into which the system has written and into which the user can write.
- The user can edit or refute a system observation. The system never argues. If the user corrects an observation, the corrected version stands; the system's prior version is not surfaced or defended.

This makes the per-record page a real artifact of the relationship between the listener and the record. Both are present in it.

### §11.6 Two questions to ask before adding anything

Two questions catch most drift before it happens.

1. *What primitive is this expressing, and does that primitive belong here?* (Cross-reference §11.2.)
2. *Is the absence of this thing more Saturday! than its presence?*

If the answer to question 2 is *yes*, the thing should not be there. Every element on a screen must be justified by what it expresses; if its absence would say something *more* — about restraint, about confidence in the listener, about not competing with the music — then it should not be there.

### §11.7 To revisit

- The exact gesture for moving between rooms. Horizontal swipe is the working assumption; iOS/Android conventions may shape the final.
- The exact affordance for invoking settings. Corner brand mark, pull-down, system gesture — needs interaction design.
- Whether system-vs-user witness paragraphs need visual attribution, or whether tone alone is enough.
- The session view's exact form — past sessions in archive, current session in listening room, but the visual rendering of either is still to design.
- The structured navigation between per-record pages — next record alphabetically, by recency, by recommendation — likely all three accessible via different gestures.

---

## §12 Cross-references to the Operating Framework

*To be written. Maps each foundation rule back to the framework principle and veto it implements, so the system is auditable against the brief.*
