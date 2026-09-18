---
id: 0020
title: A ranged volley's composition rides the command as typed counts; per-arrow leaf and type are derived along schedule order at resolve, never carried per arrow or assigned at replay
status: accepted
date: 2026-09-18
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#496"
  - "#957"
  - "docs/domain/attack-timeline.md"
tags: [ranged, combat, multiplayer, architecture]
---

# ADR 0020 — A ranged volley's composition rides the command as typed counts; per-arrow leaf and type are derived along schedule order at resolve

## Context

Under the Quiver economy (ADR 0019) a volley is one target and N arrows of
possibly several `AmmoType`s, fired from several leaves over several waves.
Three facts about one volley could plausibly go on the wire or be decided at
replay: which leaf fires each arrow, which type each arrow is, and in what
order they land. The attack timeline already fixes the last (`structural_key`
is the order primitive; `OutcomeSchedule` sorts on `(structural_key,
original_index)`; seconds are per-peer — never compare on `arrival_time`).

## Decision

The `LaunchAttackCommand`'s plan carries **`target` + `ammo_counts:
{type_id: n}`** and nothing else about the volley; N is the sum. At resolve,
the plan derives the schedule deterministically — **wave-major**: each wave,
every in-range leaf with shots left fires one arrow in nearest-first order
(distance, then `stable_id`), waves repeat to N — and **assigns types along
that schedule order in the roster's fixed `AmmoType.order`**. Owner,
2026-09-18: *"5 armor breaker shots configured first -> will land first,
regardless of what wave inside the burst they launch at."* The
`RangedHitInstance` therefore knows its type when it computes damage/status,
and the schedule order it was assigned in *is* the landing order by
construction, so nothing is re-keyed at replay and no per-arrow data crosses
the wire. Consumption (bins, per-leaf counters, volleys counter) happens at
`BattleSystem._commit` from the rebuilt command, on authority and mirror alike.

## Consequences

- A mirror rebuilding the plan from the same dict produces the identical
  schedule; the `AttackRecord` stays the only mutator (attack-timeline).
- Presentation may encode waves into `structural_key` however it likes (one
  volley = one ramp, waves back-to-back) — the encoding is not a contract, the
  order is.
- Adding an ammo type never touches the wire format.

## Alternatives considered

### Per-arrow `(leaf, type)` list on the command
Explicit, but N entries per volley on the wire and a second source of truth
the mirror must trust rather than reproduce. Rejected — a peer receives a
result or reproduces it; here it can reproduce.

### Assign types at replay from the landing order
Replay would need the roster and the counts anyway, and the hit's damage/status
must be known at resolve (it lands on the shadow world first). Rejected.

### Ordered bands (player-authored order of type runs)
The #954 mockup's maximal form. Superseded by fixed roster order + counts —
owner 2026-09-18; a drone that finds bands wanted reopens it on #954.
