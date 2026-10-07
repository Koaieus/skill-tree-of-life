---
id: 0048
title: A status's decay is authored per def (a `StatusDecay` strategy, or none); stacks stay uncapped with no per-tick clamp; rows differ in character, never in numbers
status: accepted
date: 2026-10-06
deciders: owner (supersede hard, keep uncapped and no clamp, the per-row decays, carry 0022 d3's core); pass (the character rule's wording, accepted by the owner)
supersedes: [0022]
superseded-by: null
revisit-when: null
sources:
  - "#1448"
  - "#1318"
  - "docs/design/aspect_matrix.md"
  - "effects/status/decay/"
  - "effects/status/status_def.gd"
tags: [combat, status, dot, balance, design]
---

# ADR 0048 — Status decay is authored per def; rows differ in character, never in numbers

## Context

ADR 0022 (2026-09-20) gave every DoT one global decay (stacks halve each tick) and one slot per defensive axis (bulk, armour, floor, regen). The #1318 aspect-matrix rounds then designed rows whose identity *is* their decay: a −1 Poison, a fractional Weakness, a Greed that never decays, a Bleeding whose fade ramps while it rests. Rows also landed beside each other on the same axis. Halving could express only one of these, and the axis slots forbade the rest. `StatusDef.decay` already holds a swappable `StatusDecay`.

## Decision drivers

- A row's feel (trigger, decay, spread) must be authorable per row, with no global rule to fight.
- Counterplay comes from fading, cures and not getting hit, never from a ceiling.
- A new row must have a placement test that is not "is its axis free?".

## Decision

Owner, 2026-10-06: *"ADR 22 must be superseded hard, these design sessions since it have brought a lot of good designs we are now working out"*. Nothing in 0022 stays live except what is restated here.

1. **Decay is a per-def strategy.** `StatusDef.decay` holds a `StatusDecay` (`FlatDecay`, `FractionDecay`, `RampDecay`), or `null` for no decay. Each row's shape is the owner's call for that row (#1318, `aspect_matrix.md`): Weakness, 10-06, *"fractional sounds best here, some more sensible recovery, and keeping someone at near-0 power requires consistent application of these stacks"*; Greed, 10-06, *"Greed no decay for now; …"*; Bleeding, 10-06, a ramp over flat −1 and fractional, *"we track the current decay value and calculate the next from it, easy peasy"*.
2. **Stacks are uncapped and there is no per-tick clamp** (both kept from 0022 by the owner on 10-06). Owner, 2026-09-20: *"each of the DoT types may become dangerous/deadly when applied in sufficient amounts … massive poison stacks? you're DOOMED."*
3. **Flat stacks per hit, authored on the applier** (`stacks_stat_id`). Hit size never scales stacks. This is 0022 decision 3's core, carried here by the owner on 2026-10-07: *"Carry 3, move 5 to design"*. The potency and resistance clauses stay overturned (ADRs 0029, 0031).
4. **Co-existence is placement plus character.** A row sits in the school whose verb it performs or whose strength it turns bad (the placement rule, accepted by the owner on 2026-10-05). Rows differ in character (trigger, decay, spread), never in numbers, so two flat-HP DoTs may coexist when their characters differ (the round-9 pass's wording, accepted by the owner on 2026-10-06). On Exposed beside Poison, owner 2026-10-06: *"if we would add a 3rd row to each, this would 100% be in it"*.

0022 decision 5 (Wither below zero) is design, not architecture. It moves to the Wither row of `aspect_matrix.md`.

## Consequences

- A new status picks its decay in the Inspector. The tooltip's "−N per turn" clause comes from `StatusDecay.describe`, so the readout cannot drift from the arithmetic.
- Total damage per stack now differs by row. A flat −1 row's total is quadratic in stacks, which is accepted: a big stack is meant to be a threat.
- A shape that needs history (the ramp) reads it from the row (`NodeStatus.decay_step`), never from the shared def.
- The defensive axes stay a vocabulary for what a row answers. They no longer allot slots.

## Alternatives considered

### Global halving (0022's rule)
Lost on the first driver: one curve for every row erases the per-row character the matrix designed. 0022's own ground was that flat decay is quadratic. That ground is dead, because the owner accepted quadratic totals (Bleeding's arithmetic in `aspect_matrix.md`, "Poison's 5 pay 15"). **Most likely to be revived**, as a default shape for a new row that has no decay call yet. It lives on as a `FractionDecay` of 0.5, never as a rule.

### One DoT per defensive axis
Lost on the third driver: it forbids Exposed beside Poison and Bleeding beside both. It rejects rows for their slot rather than their character.

### A per-tick damage clamp
Dead. The owner rejected it twice (2026-09-20 in 0022, again on 2026-10-06).
