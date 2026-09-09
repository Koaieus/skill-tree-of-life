---
id: 0009
title: The victory condition is a swappable resource; last-camp-standing is the first, not the only one
status: accepted
date: 2026-08-21
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#460"
  - "docs/domain/victory-system.md"
tags: [victory, session, architecture]
---

# ADR 0009 — The victory condition is a swappable resource

> **Backfilled 2026-09-09** from `docs/domain/victory-system.md`, which recorded
> this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

Before #460 a run had no terminal state: you played until you stopped. Adding one
meant deciding two things at once — *what* ends a run, and *where that rule lives*.

## Decision

**Last camp standing, as a resource the run swaps rather than a rule the system
hardcodes.**

> **Owner call 2026-08-21:** "be the only camp that survives — no living hostile
> entities remain. **Dormant Cores do not count** (`blocker` in code); they are
> inert scenery, not a camp that can win or lose."

And, on where it lives — pluggable *"because multiplayer setups will want
different conditions"*; last-camp-standing is **"the first and the default, not
the only one"**.

So `VictorySystem` owns the **when** and the **once** — it reacts to death,
latches, and is the sole emitter of `Events.run_ended` — while the
`VictoryCondition` resource owns the **what**, as a pure
`evaluate(ctx) -> RunOutcome?`.

## Consequences

- **A new mode swaps one resource** and inherits latching, signal timing and the
  death trigger for free. That split is the whole return on the decision.
- **Survival is measured in living entities, not roster seats.** A camp whose
  participants are all dead has lost, even though its `Participant`s are still in
  the roster.
- **Camps are compared by `Faction.id`**, matching `Entity.attitude_to` — two
  copies of one `.tres` are one camp, not two.
- **Single-player needs no special case.** The player is one counting camp and the
  AI is another, so dying is a LOSS and clearing the board is a WIN, straight out
  of the same rule.
- **`RunOutcome` had to become point-of-view-free** — `winning_camp` and
  `turn_count`, nothing about "you". A condition that does not know who is
  watching cannot phrase its answer for them.
- **DRAW must be reachable**, which forces evaluation to be coalesced one per
  frame rather than inline per death. Deaths arrive one signal at a time;
  evaluating inline would announce a WIN on the second-to-last death before the
  last one fired.

## Alternatives considered

### Hardcode last-camp-standing into `VictorySystem`

Fewer files, and correct for exactly the mode that existed. It lost on the owner's
own forward look — multiplayer modes were already known to want different
conditions, and retrofitting a seam through a system that also owns latching and
signal timing is strictly more work than authoring it as one.

### A point-of-view-carrying outcome ("you won" / "you lost")

Rejected with the split: the condition evaluates once for the whole run, but a
hot-seat or spectating client renders it for whoever is looking. Baking the
viewpoint into `RunOutcome` would mean re-deciding the run per viewer.
