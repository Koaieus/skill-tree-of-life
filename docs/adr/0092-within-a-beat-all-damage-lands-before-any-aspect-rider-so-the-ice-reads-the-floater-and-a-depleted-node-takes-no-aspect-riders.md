---
id: 0092
title: Within a beat all damage lands before any non-elemental aspect rider, so Frozen's damage breaker reads the mitigated number the floater shows, and a node the beat's damage depletes takes none of that beat's aspect riders
status: accepted
date: 2026-11-11
deciders: owner (aspect riders after damage, the depleted node); owner+agent (the beat scope, put by the lead and accepted)
supersedes: [0067, 0082, 0083, 0091]
superseded-by: null
revisit-when: "the first-hit loss to Malediction, Rend or Shredder reads as gutting them in play, or armor-hardened ice proves unwanted (fallback: the ice reads the arrival unmitigated, a Frozen-only exception)"
sources:
  - "#1716"
  - "docs/design/elements.md"
  - "docs/domain/status-effects.md"
  - "attack/outcome/status_instance.gd"
  - "attack/outcome/hit_landing.gd"
  - "attack/formulas/mitigation.gd"
  - "test/unit/attack/test_rider_order.gd"
tags: [combat, on-hit, status, elements, determinism, architecture]
---

# ADR 0092 — All damage of a beat lands before any aspect rider; the ice reads the floater's number

## Context
ADR 0067 §1 landed a status rider before its paired hit (`StatusInstance.land_priority` → `BEFORE`), so a Curse lifted its own hit's floor and a Hex could be spent by its own crit; ADR 0083 §3 kept that order (owner, 2026-11-10). ADR 0091 §3 then had Frozen's damage breaker read the raw amount as thrown, because a mitigated read taken before the hit's own riders landed would drift from the number that finally lands. The owner called that drift gaslighting (2026-11-11: *"the actual hit resolves differently compared to the check at the start. And that feels like gaslighting the player."*). Under ADR 0082 every aspect rider lands in stage two, so per-landing order alone still lets a sibling's or an earlier generation's Curse move a later floater that no read saw. Terrain riders (Heat, Cold, Charge) land in stage one and are not in question. Nothing elemental is built.

## Decision drivers
- **The read is the floater:** the number a breaker tests is the number the player sees land.
- **One landing order everywhere,** no Frozen-only exception.
- **Order independence within a beat** (ADR 0091): siblings and generations see the same read.
- **Stage two never changes reach** (ADR 0082): no aspect rider folded into stage one.
- **A status on a dead node means nothing.**
- **Small and replay-safe:** list order stays the tiebreak; `AttackRecord` keeps shipping hits in list order.

## Decision
1. **Non-elemental aspect riders land after damage, beat-scoped** (owner, 2026-11-11: *"Maybe non elemental riders (curse poison hex etc) land after damage after all. Might be a simpler split. Curse riders then only take effect on the next hit, which is fine"*; then, on the lead's beat-scoped wording, *"sounds agreeable"*). Within a beat, stage two lands every entry's damage, then every entry's aspect riders (Curse, Poison, Hex, Sunder, Wither, Bleeding, Marked), each half a stable partition in list order, never a sort. A Curse takes effect from the next beat. Terrain riders stay in stage one.
2. **Frozen's damage breaker reads the mitigated number:** `Mitigation.compute` (armor and the `min_damage_taken` floor) on the arrival's amount, crit and load already in, against the node as it stood before the beat. That is the floater's number. Each arrival is still tested alone (ADR 0091 §4); the "% max health" breaker stays.
3. **A node the beat's damage depletes takes none of that beat's aspect riders** (owner, 2026-11-11: *"also if damage kills nodes it makes no sense applying statuses after"*).

**Falls:** 0067 §1 and its consequence *"A curse arrow deals at least its own raised floor; a hex can be spent by its own hit's crit (intended)"*; 0083 §3; 0082 §2's *"the other status riders, then the damage"*; 0091 §3 (raw as thrown) and its *"armor never hardens ice"*. **Stands:** 0067 §2 and §4 (placement, the memoized gate), §3 in kind (the partition moves damage ahead, never a status, so no gate is decided early); 0082's two stages; 0091 §1, §2 and §4.

## Consequences
- Every arrival of every generation reads what its floater shows; nothing a rider does moves armor or floor between the read and the landing.
- Armor and the floor harden ice: a Bolt of 12 on Bunker ice floats 6 against a threshold of 7 and holds.
- First hit only, every later beat unchanged: Malediction's first cast lands 5, not 10; Rend's lands 5, not 10, on an armor-0 node; Shredder's contact no longer goes through the armor it just broke; a Hex is no longer spent by its own hit's crit. A killing hit's Curse or Sunder is lost.
- The AI pricers (`ai_combat_scorer.gd`, `ai_blade_rollout.gd`), which already price a hit without its riders, become exact.
- Old recordings and RESOLVE fingerprints change: a version bump, not a desync.

## Alternatives considered
### Frozen takes the arrival unmitigated (ADR 0091 §3 as written)
Keeps "armor never hardens ice" but lost on *one landing order*: the ice alone reads a number no floater shows. **Most likely to be revived** if armor-hardened ice proves unwanted.
### Riders first, with armor and floor read from a per-beat snapshot
Keeps 0067 untouched; lost on *the read is the floater*: the floater disagrees with the live defense card mid-beat.
### Per-landing order only (each landing's damage, then its own riders)
Lost on *order independence*: a sibling's or an earlier generation's Curse moves a later floater that its read never saw.
### The arrival's own aspect riders land before the read
Lost on *stage two never changes reach*: it folds aspect riders into stage one.
### Crit and blade only
Lost on the owner's own breaker, *"a hit that deals X amount of % max health"*.
### Show the thrown number at the ice
Lost on *one landing order*: a second floater rule for Frozen alone.
