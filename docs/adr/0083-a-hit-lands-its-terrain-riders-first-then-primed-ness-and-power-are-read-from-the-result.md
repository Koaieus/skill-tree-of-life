---
id: 0083
title: A hit lands its terrain riders (Heat / Cold / Charge) first, then primed-ness and power are both read from the result, so the hit that tips a node over T sets it off itself; Frozen reads at two points — a copy's absorption on arrival, the path-end and break check after the riders land; crit conditions still read the pre-hit node and aspect riders still land before damage — supersedes 0082 §1's "primed states read pre-hit" in part
status: accepted
date: 2026-11-10
deciders: owner
supersedes: [0082]
superseded-by: null
revisit-when: "a crit condition has to read the terrain its own hit lands (it would move behind the riders), or a rider tipping its own node makes a one-stack hit set off go-offs too cheaply to keep"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/adr/0082-a-hit-resolves-in-two-stages-terrain-gathers-the-target-set-then-payload-lands-per-target.md"
  - "docs/adr/0067-a-status-rider-lands-before-its-paired-hit-and-the-hits-gate-is-a-memoized-step.md"
tags: [combat, on-hit, elements, status, reach, determinism, architecture]
---

# ADR 0083 — A hit lands its terrain riders first; primed-ness and power are read from the result

## Context
ADR 0082 §1 (2026-11-09) had stage one read a node's primed states as they were before the hit, land the element riders, then read power post-land: a hit's own Heat fed the blast it triggered, but a hit could not prime the node it landed on, and the Frozen check sat wholly on the pre-hit node. That pre-hit read was a pass refinement, not an owner call. On 2026-11-10 a cast came to carry a shape and its terrain riders as separate things, and the reach became the node's primed state combined with the cast's shape, so a read taken before the riders landed described a node the cast had not yet touched. Nothing elemental is built.

## Decision drivers
- **One read point:** primed-ness and power come from the same terrain, so a go-off never has a state from one snapshot and a size from another.
- **The reach is primed state plus shape:** both halves are read once the cast's riders are on the node.
- **An absorbed copy lands nothing:** whether a copy is admitted has to be known before its riders could land.
- **No re-evaluation:** a hit's crit and damage are its own facts, fixed before it lands (ADR 0082).
- **Shipped order per target stands:** riders before their hit (ADR 0067).

## Decision
Owner, 2026-11-10: *"first resolve terrain riders (only: heat/cold/charge) - then resolve hit reach + local reach"*.

1. **Land, then read.** At each node of stage one the element riders land (Catalyst converting as they add) and Heat × Cold nets; the node's primed states and their power are then both read from the result. The hit that tips a node over T sets it off itself. This replaces 0082 §1's "primed states read pre-hit, power read post-land".
2. **Frozen reads at two points** (owner, 2026-11-10, picked *admit on arrival, the rest after riders* over all of Frozen reading pre-hit): whether an arriving copy is absorbed is checked against the node as it arrives, and an absorbed copy lands no riders; the path-end and the break check read after the hit's element riders land, as Burning and Shocked do.
3. **Per target, aspect riders still land before damage** (owner, 2026-11-10, asked whether damage now lands before the aspect riders: *keep riders before damage*); ADR 0067 is unchanged.
4. **Crit conditions are still evaluated at the head of the gather, against the node as it was before this hit** — the owner's 2026-11-09 build call recorded with ADR 0082, unchanged: the crit is a fact of the hit, fixed before its riders land.
5. **Same-beat hits** keep the owner's 2026-11-09 *one snapshot per beat*: their element riders land as sums on the pre-beat terrain and the go-offs are read from that summed terrain.

**Falls:** 0082 §1's pre-hit primed read and its pre-hit Frozen check. **Stands:** the rest of 0082 — the two stages, absorption of an under-threshold copy, the copy's crit, Catalyst's two triggers.

## Consequences
- A hit carrying +1 Charge onto a node one short of Shocked arcs from it; a hit carrying +1 Heat onto a 5-Cold node is read against 4 and thaws for itself.
- A hit that freezes a node ends its own walk there; a crit or heavy hit that freezes it shatters it at once; a Heat hit that thaws it passes through without a shatter.
- A Cold copy onto a Frozen node lands nothing, so only a direct Cold hit deepens a freeze, as before.
- Priming is no longer a turn of set-up paid before the pay-off: a single rider on a node sitting at T is enough, and tuning has to price that.
- A crit condition reading terrain (Thermal shock) reads the node before the hit's riders, while the reach reads it after: two read points inside one hit, on purpose.
- Stage one's steps at a node are admit / land / read, where 0082 had read / land / settle.

## Alternatives considered
### Keep the whole pre-hit read (0082 §1)
Lost on *the reach is primed state plus shape* and *one read point*: the cast's riders and its shape resolved against different terrain, and a go-off's state and power came from two snapshots. **Most likely to be revived** if self-tipping hits prove too cheap.
### All of Frozen reading pre-hit
Lost on *one read point*: Frozen would be the one primed state not read where Burning and Shocked are, and a hit that freezes or thaws a node would be judged against the node it had already changed. Rejected by the owner's pick in §2.
### All of Frozen reading after the riders
Lost on *an absorbed copy lands nothing*: the copy's riders would have to land before the node could refuse them.
### Damage before the aspect riders, per target
Lost on *shipped order per target stands*: the owner was asked and kept ADR 0067's order.
