---
id: 0010
title: Contest membership is a predicate the victory condition owns, not a flag on Faction
status: accepted
date: 2026-08-22
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#517"
  - "#460"
  - "docs/domain/victory-system.md"
tags: [victory, session, architecture, entity]
---

# ADR 0010 — Contest membership is a rule the condition owns

> **Backfilled 2026-09-09** from `docs/domain/victory-system.md`, which recorded
> this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

[ADR 0009](0009-the-victory-condition-is-a-swappable-resource.md) put the victory
rule in a swappable resource. It left open *who counts* as a contestant, which
started as `Faction.counts_for_victory` — a bool per camp.

That could not express a **per-entity** exception without minting a faction for
it, and Dormant Cores were exactly such an exception.

It was also actively dangerous as it stood. Dormant Cores and AI opponents both
sat on `npc.tres` — `entity.gd`'s default faction, and what
`procgen_play_sandbox.gd` hands every AI participant. Opting `npc.tres` out under
the per-camp flag would have left one counting camp at spawn and ended every run
instantly, and that failure is **invisible to a hand-built two-camp test**.

## Decision

**Contest membership is a `ContestantRule` — a pure `includes(ent) -> bool` that
the `VictoryCondition` owns.**

> **Owner call 2026-08-22:** *"i feel like the game mode decides the victory
> conditions, and entities themselves just should be agnostic of all this… i
> think a predicate (customizable to any condition) would be a more useful
> construct than a single bool… i feel like victorycond would be the one to apply
> them anyway."*

The one rule so far is `ExcludeGroupRule`, defaulting to
`session/victory/rules/exclude_scenery.tres`: everyone except members of the Godot
group `scenery`, which `entity/blocker/blocker_entity.tscn` authors on itself.
`Entity` gains no field and learns nothing about victory.

The per-entity exception is not the justification for the shape:

> **Owner call 2026-08-22:** the per-entity exception is *"a free consequence,
> not the justification"*

— take it because a group read costs the same either way, but do not grow
`ContestantRule` to anticipate a tutorial. **Bespoke run-end logic is a
`VictoryCondition` subclass**, not a cleverer rule.

## Consequences

- **The `npc.tres` failure class is gone.** The handle is on the *scene*, not on a
  resource other entities share.
- **A null rule means everyone counts** — never a crash, never a run that can no
  longer end.
- **The group means OUT, never IN.** `VictorySystem` lives in `game_root.tscn`, so
  a GUT fixture or a sandbox tab has nothing to stamp anyone; under an "in"
  polarity every evaluation would be an instant DRAW. Only the exception authors
  itself, and today that is `blocker_entity.tscn` alone.
- **It is a filter, not a second enumeration.** `build_context` walks
  `Entity.GROUP` exactly once; a rival walk would silently drop every
  `Entity.new()` fixture and sandbox entity out of victory evaluation.
- **This is the shape the neighbours landed on** — XCOM 2 queries unit traits from
  the mission objective, Unreal's `AGameMode` owns match state while actors carry
  `Tags`.
- **`Faction.targeted_by_ai` deliberately did not follow.** "Worth an NPC's AP" is
  genuinely camp-level — you shoot at camps, not individuals. A per-entity version
  reading the same `scenery` group would be a drop-in, since `AiRecon` already
  resolves the flag per owning entity, but that is its own decision.

## Alternatives considered

### `Faction.counts_for_victory`, the per-camp bool

What was there. It cannot express a per-entity exception without minting a faction
for it, and the one exception that existed shared a faction with the AI opponents —
so setting it would have ended every run at spawn. **Dead**, and worth knowing it
was dead in a way no two-camp test could show.

### Push membership at spawn, as a Godot group stamped by a run-start sweep

Materialise the answer once instead of asking per evaluation. Rejected on ordering
and on polarity: the sweep would have to run after `victory_system.condition` is
assigned — later than `_setup_level` — and would then re-stamp anything a level
deliberately un-stamped, because a boolean group cannot tell "not yet stamped"
from "deliberately out". There is also no `entity_spawned` signal and four
creation paths.

**Not a dead ground for a *view*:** a materialised view computed from the same
rule stays purely additive if save/replay/spectating ever wants one. What is
rejected is the pushed group being the *source of truth*.

### Grow `ContestantRule` to cover anticipated modes

Rejected by the owner's own framing above — the predicate is a free consequence of
a group read, not a feature to build out. A mode that needs bespoke run-end logic
subclasses `VictoryCondition`.
