# Saturday! — Agent guide

Before making any changes to this codebase, read the following.

## Required reading

1. **`./shared-docs/foundation/constitution.md`** — operational rules, banned patterns, vocabulary, token values, motion timing, voice rules. Covers most design and coding decisions. Required before any UI work or copy change.

## Reference

2. **`./shared-docs/foundation/saturday_design_system_foundations.md`** — the full design system specification. Read for depth on color, typography, spacing, motion, lighting, voice, or surface decisions when the constitution refers you here.

3. **`./shared-docs/foundation/saturday_operating_framework.md`** — the original brand operating framework. Read when reasoning about *why* a rule exists, or when making judgment calls in cases the constitution doesn't explicitly cover.

## Precedence

When documents disagree, the order is: **operating-framework → foundations → constitution**. The constitution is the operational mirror of the foundations; the foundations is the source of truth for the design system; the operating framework is the source of truth for the brand. If you change behavior in a way that drifts from the constitution, update the constitution to match the new reality — or revert the change.

## Brand assets

- Wordmark: `./shared-docs/foundation/Saturday_Logo_Final.svg`
- App icon: `./shared-docs/foundation/saturday-icon.svg`

The wordmark is the only place an exclamation point appears in user-facing content. Verify before merging any PR that adds copy.

## Two questions for every change

1. What primitive is this expressing, and does it belong here?
2. Is the absence of this thing more Saturday! than its presence?

If the answer to question 2 is yes, the change should not be merged.
