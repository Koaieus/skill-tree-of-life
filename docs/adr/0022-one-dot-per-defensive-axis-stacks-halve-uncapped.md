---
id: 0022
title: One DoT per defensive axis; a status is uncapped stacks that halve; no per-tick clamp
status: accepted
date: 2026-09-20
deciders: owner
supersedes: []
superseded-by: null
sources:
  - "#952"
  - "docs/design/damage_over_time.md"
  - "effects/status/status_def.gd"
  - "effects/status/poison.tres"
tags: [combat, status, dot, balance, design]
---

# ADR 0022 — One DoT per defensive axis; a status is uncapped stacks that halve; no per-tick clamp

## Context

The shipped poison (#874) was `% of max HP`, unmitigated, linear decay from a
cap of 5 with damage proportional to power: 25% of max HP on the first tick,
75% over five, lethal in four turns of sustained application against *any*
node. It countered bulk, armour and the floor at once, so it was the only DoT
worth having, and it made a 20-HP node and a 2000-HP node die on the same
clock. The #952 session asked what a *family* of DoTs should be, given that an
entity's defence is a point in several dimensions (bulk, armour, floor, regen,
aura, topology) and each dimension blocks a different shape of damage.

## Decision

1. **One DoT per defensive profile.** Poison (flat, unmitigated) answers armour
   and the sub-zero floor; corruption (% max HP) answers bulk; curse (raises
   `min_damage_taken`) answers the bunker; wither (multiplies healing received,
   below zero) answers the fortress. Owner: *"yes 100%."*
2. **A status is one number, its stacks, and stacks halve each tick.** Total
   effect of N stacks applied once is 2N — linear in what the attacker did.
   Stacks are **uncapped**. Flat decay with damage ∝ power is quadratic
   (N(N+1)/2) and is retired for DoTs; blindness and armor-break keep it as a
   per-def mode.
3. **Flat stacks per hit, authored on the applier; hit size never scales
   stacks.** Attacker potency and defender resistance are per-type percent
   stats applied once at land; the row still holds one number.
4. **No per-tick clamp.** Owner: *"each of the DoT types may become
   dangerous/deadly when applied in sufficient amounts … massive poison stacks?
   you're DOOMED."* Counterplay is fading, resistance, cures and not getting
   hit — never a ceiling.
5. **Wither below zero is a special case:** a negative heal deals damage that
   does *not* close the regen gate, so the ramp keeps climbing and the node
   heals itself to death. Owner: *"it ruins your healing to making you
   effectively undead."*

## Consequences

- `StatusDef` grows a decay mode and a display anchor; `power_max <= 0` means
  uncapped. Every DoT def authors FRACTION decay.
- Eight new board stats (`<type>_potency`, `<type>_resistance`); procgen rolls
  potency only as `INCREASE`, never a flat point on a stat designed at 1.
- A fully corrupted node dies, at level 1 too. That is the design.
- Each DoT gets an arrow, an addon and one to two spells as content (ADR 0023).

## Alternatives considered

### Keep %-max poison with a cap
**Rejected.** Counters everything; trivial at low HP and certain death at high HP — the inverse of the intended profile.

### Fixed duration refreshed on apply
**Rejected.** Linear, but a second field per row, a resync column, and the "last applier resets vs max" fork.

### Per-hit instances (PoE)
**Rejected.** Linear and faithful; the slice becomes a list and every reader changes.

### Stacks as a fraction of damage dealt
**Rejected.** Reintroduces the pre/post-mitigation legibility problem; the per-applier float already lets a big hit poison big.

### A per-tick damage clamp (≤ k% max HP)
**Rejected by owner.** A full poison build should kill in one turn.

### Resistance as faster decay
**Deferred**, reserved as a class identity; incurred-stacks resistance mirrors potency and snapshots at apply.
