---
id: 0004
title: The allocation-level magnitude ladder is linear
status: accepted
date: 2026-08-05
deciders: owner+agent
supersedes: []
superseded-by: null
sources:
  - "#376"
  - "#784"
  - "skill_node/skill_node.gd:1288"
tags: [stats, balance, skill-node, design]
---

# ADR 0004 — The allocation-level magnitude ladder is linear

> **Backfilled 2026-09-08**, dated to the original call in #376. The record
> exists because the decision was re-derived from memory a month later, during
> the design of #784, and re-affirmed on the same grounds plus new ones. Twice
> settled from memory is the signal for a record.

## Context

A `SkillNode` has a cap (`stake_level`, 1..3) and a fill (`allocation_level`,
0..cap) — a node reads `M/N`. Filling a node further has to *do* something, and
#376 settled the mechanism: a **mutator** on the SkillNode retunes its modifier
resources in place on every `allocation_level` change, reaching both the
node-local bin and the modifiers the node grants to its owner's entity board.

That left the open question this record answers: **what curve?** The mutator
calls `_local_scale(al)` and the body is one line, deliberately — #376 decision 1
chose linear while explicitly parking the alternative: *"Linear ladder,
plug-and-play. Swap to doubling/curve later = one line."*

The pressure toward a curve is real. This is a game with several multiplicative
ladders already, and a fully-invested node is a large commitment that ought to
feel like one.

## Decision

**`_local_scale(al) = max(al, 1.0)` — the ladder is `1 : 2 : 3`, and it applies
uniformly to every scaling modifier: procgen-rolled, addon-carried, and
node-granted-to-entity alike.** There is no per-source curve and no opt-in
exponential tier.

Two parts of the law are load-bearing and are part of this decision, not
incidental implementation:

- **ADD ops scale by the ladder directly** — `value × ladder(al)`, exact for
  integer ladders so round-trips do not drift (#376 decision 6).
- **MULTIPLY scales its growth part**, not its whole value:
  `X(al) = 1 + (X − 1) · ladder(al)` (`_laddered_multiply`,
  `skill_node/skill_node.gd:1292`). So SpikeRing's `×1.5` reaches `×2.5` at a
  full 3/3 node, not `×4.5`.

Per-modifier departures remain available through
`StatModifier._local_scale_override` (`stats_system/stat_modifier.gd:129`), which
exists for genuinely exotic content — a modifier that changes *composition*
rather than magnitude, say. It is not the hook for re-introducing a global curve
one modifier at a time.

## Consequences

- A modifier on a full 3/3 node is worth **three times** its authored value. A
  `+30` node becomes a `+90` node — already, in the owner's words, *"quite
  strong"*.
- **The cost curve is convex, so the value curve must not be.** Taking one
  unallocated node from `0/1` to `3/3` costs **5 SP and 2 AP** (owner, 2026-09-08):
  2 SP + 2 AP staking, 3 SP allocating — against 1 SP for a plain `1/1`. Stacking
  an accelerating value curve on an accelerating cost curve reads as a snowball;
  the intended read is a considered investment with somewhat *diminishing* returns
  per point.
- **The superlinear channel already exists, and it is `addon_slots`.**
  `addon_slots = base(0) + allocation_level` is authored as an intrinsic on the
  node board, so a 3/3 node holds **three addons**. Each slot is a whole addon,
  not a magnitude bump — chunky rather than smooth, and a choice rather than a
  number going up. That is the better home for "a big investment feels big".
- **Compounding with `TierLadder` is where the real spike lives.** Procgen's v4
  tier ladder is `V[t] = 2^t − 1` → `[1, 3, 7, 15]`
  (`procgen/pools/tier_ladder.gd`), a *different axis*: tier is what was drawn,
  allocation level is how full the node is. They multiply — a T3 modifier on a
  3/3 node is **×21** of a T1 baseline. Any future argument that the game lacks
  scaling has to account for this number first.
- Linear is legible at the table. A player can price a stake without doing
  exponent arithmetic, and — the owner's framing, 2026-09-08 — *"in a game where
  we already have mad scaling in many ways, linear is a breath of fresh air
  almost."*
- Downstream, #784 (blockers pre-staking and filling the node they squat on) is
  balanced against ×3 and three addon slots, not against a curve.

## Alternatives considered

### A global exponential ladder: `2^al − 1` → `1 : 3 : 7`

The swap #376 parked: change one line so every scaling modifier grows
`1 / 3 / 7` with fill.

**Why it lost:** it is the wrong shape against the cost curve. A full node
already costs 5 SP + 2 AP where a plain one costs 1 SP, so the marginal point is
getting more expensive as you buy it; making the marginal point simultaneously
more *valuable* turns a considered investment into a snowball and pushes every
build toward a few maximally-stacked nodes. It also compounds with `TierLadder`
into ×49 for a T3 modifier on a full node, which is not a balance surface anyone
asked for.

### The same exponential, but for addon modifiers only

Keep rolled modifiers linear; give addon-carried modifiers `1 : 3 : 7` via a
`_local_scale_override`, on the reasoning that an addon is a deliberate
investment and should scale harder than a random roll.

**Why it lost:** the premise is already satisfied by a different channel —
`addon_slots` grows with fill, so a filled node rewards addons by *holding more of
them*. Scaling their magnitude on top double-counts the same investment. It also
splits one law into two, which is the thing #376 decision 2 ("universal law
applies by default") exists to prevent: two ladders means every future content
author has to know which bin their modifier landed in.

### `value × ladder(al)` for MULTIPLY, alongside the ADD ops

The intuitive reading — `×1.5` at ladder 7 becomes `×10.5` — and the one that
made the exponential proposal look stronger than it was.

**Why it lost:** it is scale-dependent, so it is not a law. Under it a `×1.05`
modifier grows to `×7.35` — a gain of 6.30 — while `×1.5` grows to `×10.5`, a
gain of 9.00; but relative to the *effect* each modifier actually has, the weak
one gains 126× its original bonus and the strong one only 18×. Ranking inverts
depending on where the authored value sits relative to 1.0. The growth-part
convention `1 + (X − 1)·ladder` is the only form that treats a multiplier's bonus
the way the ADD law treats an addend, which is why #376 decision 6 scoped
`value × ladder(al)` to the ADD ops in the first place.

## Dead grounds

Recorded so a fourth pass does not pick them up:

- *"Addons should scale harder than rolled modifiers."* Answered: `addon_slots`
  is that scaling.
- *"The game needs a bigger payoff for full investment."* Answered: ×3 magnitude
  × 3 addon slots, compounding with tier up to ×21.
- *"MULTIPLY barely moves under a linear ladder."* It moves by design — the
  growth part is what scales; see the third alternative.

Re-opening this needs **evidence from play**, and any proposal must price itself
against the 5 SP + 2 AP cost of a full node and against the ×21 tier
compounding.
