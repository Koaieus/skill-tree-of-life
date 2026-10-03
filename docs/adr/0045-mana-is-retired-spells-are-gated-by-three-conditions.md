---
id: 0045
title: Mana is retired — the mana pool, its regen, every spell's mana cost and every mana modifier are deleted, and spell power is gated by three conditions (knowing the spell, entity degree at the cast node, range)
status: accepted
date: 2026-10-03
deciders: owner
supersedes: [0039]
superseded-by: null
revisit-when: "Someone has the great idea that makes a cross-turn caster resource bind across the whole INT range and matter to more than one attack mode — restore from the `retired/mana` tag rather than rebuilding"
sources:
  - "#1371"
  - "#766"
  - "#278"
  - "docs/adr/0039-spell-power-is-gated-by-four-conditions-not-by-damage-tuning.md"
  - "git tag retired/mana (454dd0a)"
tags: [spells, balance, mana, stats, design]
---

# ADR 0045 — Mana is retired; spells are gated by three conditions

## Context

ADR 0039 made mana gate 3 of four spell gates: a per-entity pool, spent by spells, refilled by a per-turn regen. #766 thinned the INT transfers so the board would be the mana source. It still did not earn its place. The owner, 2026-10-03, verbatim:

> i think.. mana has to go. for now at least, pending a great idea that makes it less of a pure annoyance stat hard to make useful (either it always caps or is always available; and in 2 of 3 attack modes is entirely dead so any mana or mana regen modifiers are of 0 interest for other attack modes), so i think i have to make the call: it's time has come

## Decision drivers

- A gate that never blocks, or always blocks, is not worth having (0039's own driver). Mana either capped or was always available.
- Only magic spends mana. A mana or mana-regen roll is dead weight to a ranged or melee build, so it dilutes the INT pool for two of three modes.
- Recoverable: *"ideally done in such a way that if we later want to retrieve what we had, we could easily find it in git"* (owner).

## Decision

Owner, 2026-10-03: *"mana -> gone · mana regen -> gone · UI for mana -> gone; spell mana cost -> gone · mana related modifiers in stat board, in innate modifier list -> gone"*.

1. Deleted: the `mana` pool and `mana_per_turn` stats (defs, roster, typed accessors, the INT intrinsics on every board, the procgen pool entries); `SpellDef.mana_cost`, `AttackOutcome.mana_cost`, the `AttackRecord` wire field, the `BattleSystem` gate and deduction, the AI's affordability check; every mana UI surface (hero-sigil gauge, picker grey-out, cost labels, the "no mana" floater).
2. Spell power is gated by **three** conditions: knowing the spell, entity degree at the cast-from node, range from the cast node. A spell costs the default 1 AP every launch costs. Nothing replaces mana until a design clears the drivers above.

## Recovering it

The last master commit carrying the whole mana system is tagged **`retired/mana`** (`454dd0a`). Start from:

```
git show retired/mana:stats_system/defs/mana.tres
git show retired/mana:stats_system/defs/mana_per_turn.tres
git grep -n -i -P '(?<![a-z])mana(?![gi])' retired/mana
```

The `git grep` is the full seam map (~100 files); the removal commits close the hub's children in `sources:`.

## Consequences

- ADR 0039 is superseded; its gates 1, 2, 4 and "damage tuning is never a gate" stand. Its caster-identity slot (mana, "the one per-entity gate") is empty: design work, not a revert.
- The INT procgen pool loses two entries, so its weights renormalize. A seeded run, the authored `first_level_sandbox` run included, rolls different INT content under the same seed.
- Saves: the stat board serializes by stat id, so the world shape changes and `SaveFile.FORMAT_VERSION` is bumped. An older save is refused by the version gate.
- `ThresholdFormula` stays. `perception → sensor_range` still uses it.

## Alternatives considered

### Keep mana dormant (defs kept, unregistered or zeroed)
Rejected: the owner asked for "gone", and a dormant stat is a parallel copy every reader has to skip. The tag keeps it retrievable at no ongoing cost.

### Rework mana again (a third shape after D-34 and #766)
Not now: *"pending a great idea"*. **Most likely to be revived**, through `revisit-when`. Making mana matter to all three modes is that same idea slot, not a rejected ground.
