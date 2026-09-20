---
id: 0025
title: A default-on heal gate with an explicit raw bypass and a drift guard
status: accepted
date: 2026-09-20
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#994"
  - "#966"
  - "combat/node_combat.gd"
  - "stats_system/pool_stat.gd"
tags: [combat, healing, stats, architecture]
---

# ADR 0025 — A default-on heal gate with an explicit raw bypass and a drift guard

## Context

`NodeCombat.heal_damage` already multiplies node heals by `healing_received`
once (#966, `combat/node_combat.gd:510-520`); the `health` pool's own
`core_healing` upkeep is a plain `ADD` rate that calls `PoolStat.replenish`
(`stats_system/pool_stat.gd:191-205`) directly and never reads
`healing_received` at all. The moment an entity-hosted Wither exists (ADR 0024)
that is an inconsistency: every node heal inverts, the core's own trickle does
not. #994 asked how to close that gap for both existing and future heal
mechanics without reopening it every time a new one is added.

Owner (2026-09-20): *"All heals must consult it. Maybe a new System needed of
sorts?"* — and, stating the worry that shaped the answer: *"Worry next heal
mechanic slips through the healing_received, while we likely will encounter
cases where we'd want to bypass it explicitly and in most cases not bypass
it."*

## Decision

1. **One heal door per host.** `NodeCombat.heal_damage` is the existing node
   door; `EntityCombat` gets the twin, `heal(amount, source, raw := false)`.
   Every heal to a host's pool routes through its host's door. A negative
   product (Wither past ten stacks) is TRUE damage that **leaves the regen gate
   open** — the #966 contract, now on the pool too, routed into the pool-damage
   door of ADR 0024.
2. **Both doors multiply by `healing_received` by default; `raw := false` is
   the only bypass** — an explicit argument at the call site, not a second door
   or a flag elsewhere. The pool's `core_healing` upkeep enters through the
   entity door instead of calling `PoolStat.replenish` directly; the def stays
   declarative (the companion rate just takes the host's door).
3. **A drift-guard test fails any direct `replenish(` on `health` or
   `node_health` found outside the two doors**, naming file:line. This is what
   answers the owner's worry structurally: a future heal mechanic cannot slip
   past `healing_received` by accident, because reaching the pool any other way
   is a red test, not a missed convention.
4. **Within-turn order:** `core_healing` upkeep first, then the entity-host
   status tick — mirroring the node precedent (`test_status_tick_lifecycle.gd:6`).

## Consequences

- Every heal path — passive upkeep, an authored heal spell, a future mechanic —
  is forced through a door that already applies the multiplier; a new heal
  source cannot regress this by omission.
- `raw := true` is rare and load-bearing: visible in review, grep-able, and the
  only way a heal ignores `healing_received`.
- The `.claude/rules/stats-system.md` paragraph "pool upkeep stays declarative"
  gains one sentence: an ADD companion rate may enter through the host's heal
  door; the def still declares it.
- `hero_sigil_card` binds `health ← core_healing` as an "incoming next turn"
  band; under Wither that band shows a heal that is actually a drain — parked
  for #953's icon row.

## Alternatives considered

### A `HealingSystem`
**Rejected.** A third place that knows both boards and every heal source. The
*stat* is already the system: `healing_received` is a board-read multiplier and
heal-block is already `healing_received = 0` (a SET). A system would duplicate
what the host doors must do anyway, with no new capability.

### Gate inside `PoolStat.replenish`
**Rejected.** Moving the multiply into the pool primitive makes an ungated
replenish structurally impossible, but the gate needs host logic the pool does
not have: a negative product must become TRUE damage that leaves the regen gate
open (#966), and the multiplier is a *combined* read (entity+node bins for a
node host) that a bare `PoolStat` cannot resolve. The host door would still
exist on top — two gates to keep in agreement.

### Convention only
**Rejected by the owner's stated worry.** *"Worry next heal mechanic slips
through the healing_received"* — a convention with no enforcement is invisible
to violate; the drift guard fails the suite rather than relying on every future
author remembering the rule.
