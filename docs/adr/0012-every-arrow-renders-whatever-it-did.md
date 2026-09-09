---
id: 0012
title: Every arrow renders, whatever the landing did — a render pass never filters on outcome
status: accepted
date: 2026-09-04
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#488"
  - "#332"
  - "33a4cef"
  - "docs/domain/attack-timeline.md"
tags: [combat, attacks, vfx, ranged]
---

# ADR 0012 — Every arrow renders, whatever the landing did

> **Backfilled 2026-09-09** from `docs/domain/attack-timeline.md`, which recorded
> this decision before the ADR tier existed (see
> [ADR 0001](0001-adrs-record-decisions-domain-docs-record-behaviour.md)). The
> date above is the date of the call, not of this file.

## Context

[ADR 0011](0011-one-attack-timeline-contract-for-every-mode.md) settled that a
ranged landing whose gate fails still renders — the arrow is already in flight when
the target dies, so it arrives and plays a dud beat.

A dud is not the only non-standard outcome a landing can have. A hit may mitigate
to exactly zero, or — where the defender's net `min_damage_taken` is negative,
which `bunker_addon.tscn` authors deliberately — mitigate *below* zero and be
reclassified to `Kind.HEAL` by `NodeCombat.take_damage`.

`ArrowVolleyCoordinator.play` used to iterate `AttackOutcome.damage_hits()`, which
keeps only `Kind.DAMAGE`. A volley whose hits all flipped to heals came back empty,
the coordinator returned before spawning anything, and **the player spent the AP
and no arrow left the bow.**

## Decision

> **Owner call 2026-09-04:** *"each arrow should fire, regardless of what they do.
> render. every. arrow. damage? render. 0? render. heal? render."*

`ArrowVolleyCoordinator.play` iterates `outcome.hits` directly and **must never
filter on `HitInstance.kind`.** The generalisation: **filter at the call site that
means it, never in a render pass.**

## Consequences

- **The AP the player spent is always visible.** A volley that produced nothing
  interesting still looks like a volley; silence reads as a bug, and was one.
- **`damage_hits()` stays, and is fine.** Its remaining callers — `AiCombatScorer`,
  `AiBladeRollout` — are *scoring* passes that genuinely want damage only.
- **Every new landing kind is renderable by default.** A future outcome class
  cannot silently disappear from the volley by not being `Kind.DAMAGE`.
- **The dud beat becomes one outcome among several**, not the single special case
  ADR 0011 framed it as.

## Alternatives considered

### Filter the render pass on `Kind.DAMAGE`

What the code did. It is the reading of "render the hits" that seems obvious right
up until a hit is a heal. **Dead** — if you are about to narrow that iteration
again, this record is why not.

### Filter on "anything that changed HP" — damage or heal, but not a zero

Narrower and still wrong: a fully-mitigated landing is exactly the case a player
most needs to see, because it is the feedback that the target's mitigation is doing
something. The owner's phrasing enumerated zero explicitly for this reason.
