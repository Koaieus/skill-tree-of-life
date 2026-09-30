---
id: 0033
title: Damage and heal magnitudes round UP once, where the value is produced, so mitigation runs int-on-int; mitigation stays max(min_damage_taken, raw − armor) with negative armor applied before the floor
status: accepted
date: 2026-09-30
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "Many-hit sources (volleys, forking spells) whose sub-1 hits each round to 1 over-deliver in playtests"
sources:
  - "#1217"
  - "#1203"
  - "#1156"
  - "docs/adr/0017-combat-quantities-are-int-and-a-merged-read-floors-once.md"
  - "attack/formulas/hit_points.gd"
  - "attack/formulas/mitigation.gd"
  - "attack/formulas/ranged_damage.gd"
tags: [combat, balance, stats]
---

# ADR 0033 — Damage and heals round up where produced; mitigation stays `max()`

## Context

ADR 0017 made damage, armor and health INT stats (*"all int-on-int action"*), but the multiplied hit amount was never rounded: `ranged_damage × AmmoType.damage_scale` (poison 0.5), spell per-hop multipliers and crits reach `Mitigation.compute` as floats. #1156 floored once, at the HP door (`HitPoints.land`). That left a discontinuity: a 0.0 hit deals 0, a 0.01 hit is lifted to `min_damage_taken` (default 3), or heals where that is negative. A sub-1 unmitigated tick (corruption's `% max HP` on a small node) floored to 0.

## Decision drivers

- **Integers at each moment a value is produced**, so every stage the player reasons about is whole.
- **Damage trades stay visible:** a special arrow that halves its raw damage still hits.
- **No odd jumps** between a zero hit and a tiny one.
- **`min_damage_taken` keeps its meaning** as the least a real hit lands.

## Decision

1. **A magnitude is rounded once, where it is produced, towards the larger whole number.** Owner, 2026-09-30: *"the whole pipeline should yield integers at each right moment a value is produced"*; *"rounding up that .5 to 1 then letting it enter the mitigation pipeline as such sounds quite alright no?"*
2. **Heals round up too.** Owner, 2026-09-30: *"heals round up as well i think, if that rounding saves you, lucky you"*.
3. **Mitigation stays `max(min_damage_taken, raw − armor)`.** Owner, 2026-09-30: *"'min damage taken' is a hard minimum, iff you are to take damage, no less than that"*; *"armor doesn't reduce below min damage taken"*; *"negative armor mitigates damage upward before being raised to at least the floor"*.

## Consequences

- Pre-mitigation amounts and `armor`/`min_damage_taken` are all integers, so post-mitigation (heals included) is an integer with no second rounding. The HP door no longer rounds.
- A hit with exactly 0 damage (the scout arrow) carries no damage payload: it skips mitigation and deals 0. Any positive amount lands at least 1 before mitigation.
- Unmitigated damage (TRUE, DoT ticks) rounds up and, being positive, never heals; a 0.4 corruption burst lands 1.
- Amends the `HitPoints` contract ("floored ONCE, where it lands … never a carry or a ceiling") and reverses #1156's *"flooring to 0 seems most reasonable"*.
- Curse and negative armor do not add: the larger of the floor and `raw − armor` wins.

## Alternatives considered

### Floor once at the HP door (#1156, as shipped)
**Rejected on no-odd-jumps and int-on-int:** mitigation ran on floats and a 0.01 hit leapt to the floor.

### Round down at production
**Rejected on visible trades:** chip and scaled hits vanish, and corruption never hurts small nodes.

### Additive mitigation: `max(floor, raw − max(0, armor)) + max(0, −armor)`
Accepted by the owner earlier on 2026-09-30, then withdrawn: armor 0 with 10 flat armor break made a raw-1 hit land 13, not the intuitive 11. **Lost on the floor's meaning.** **The option most likely to be revived** if curse and armor break must combine rather than compete.
