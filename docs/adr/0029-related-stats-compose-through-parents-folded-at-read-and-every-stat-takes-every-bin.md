---
id: 0029
title: Related stats compose through declared parents folded in as overlays at read; a quantity is one stat with every bin, never a flat stat plus a multiplier stat
status: accepted
date: 2026-09-28
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "A parented read shows up in a profile, or a parent's value_changed fan-out stalls a frame"
sources:
  - "#1154"
  - "docs/domain/stat-knobs-and-bins.md"
  - "docs/design/damage_over_time.md"
  - "stats_system/stat.gd"
  - "entity/core/ninja_core.tres"
tags: [stats, architecture, authoring, balance, dot]
---

# ADR 0029 — Related stats compose through parents folded at read; a quantity is one stat with every bin

## Context

Families of stats have piled up with no way to address the family. The Ninja core aura boosts "damage", which is three stats (`blade_damage`, `spell_damage`, `ranged_damage`), so it was authored three times and silently misses the next damage type. The DoT vocabulary added a per-family `<family>_stacks_per_hit` plus a shared `dot_stacks_per_hit`, summed as separately folded values, so a `MORE ×2` on one multiplies only that stat's own 0 — and a `<family>_potency` that is the same quantity's multiplier living in a second stat. `Stat.get_value_with(overlays)` already folds any list of `ModifierBins` as one `(base + Σadd) × (1 + Σinc) × Πmore + Σbonus`.

## Decision drivers

- DX: a modifier aimed at a family is authored once and reaches members added later.
- Performance: no new dirty-propagation machinery; one fold, one floor (ADR 0016), and the readout is the number the game uses.
- A stat is a target (stat-knobs-and-bins §1): anything targetable takes every bin.

## Decision

1. **A stat may declare parents; a read folds its parents' bins in as overlays.**
   Owner, 2026-09-28: *"Parent stats could also just be at the readout right,
   like innately adding parents to the overlay list."* Invalidation is one
   `value_changed` subscription per parent: *"a single signal subscription per
   parent would suffice."* Parenthood is data on the def, never a code subclass.
2. **A quantity is one stat with the full bin set.** Never a flat-only stat
   paired with a multiplier-only stat for the same quantity. Owner, 2026-09-28:
   *"no more potency stat"*, *"that one stat would be a full stat. Bins like
   base, mults, everything."* An applier's authored amount enters as a
   `base_add` overlay (the stat-knobs-and-bins §5 cast-range shape).

## Consequences

- A family modifier (+% damage, +1 DoT stacks) lands once on the parent and reaches every child, present and future; sibling increases share one sum (+20% `damage` and +10% `blade_damage` = +30%).
- A parent-level flat is uneven across children: hit counts differ by orders of magnitude (ranged: tons; magic: some to tons; melee: lots but not tons). Owner, 2026-09-28: balancing is *"more tight if flat amounts (base or bonus) are modified"* on a parent. Content treats parent flats as rare.
- A child's memo is invalidated by its parents' signals as well as its own bins.
- Overturned: the `<family>_potency` rate-stat row of stat-knobs-and-bins §5, and ADR 0022 decision 3's potency clause (resistance placement there still stands); potency folds into the stacks stat's multiplier bins.

## Alternatives considered

### Author a family modifier once per member
**Rejected** on DX: the Ninja aura in triplicate, stale the day a damage type is added.

### No shared stat; a family affix is one modifier replicated onto each member
**Rejected** on DX, same grounds at authoring time; also no single readout row for the family. **Most likely to be revived** if parent fan-out proves costly.

### A flat stat plus a multiplier stat per quantity (`*_stacks_per_hit` + `*_potency`)
**Rejected** on "a stat is a target": each would take bins that mean nothing on it, and a `×2` on the flat stat multiplies only its own extras.
