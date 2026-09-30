---
id: 0039
title: Spell power is gated by four independent conditions — knowing the spell, entity degree at the cast node, mana, range from the cast node — never by tuning damage down
status: accepted
date: 2026-08-03
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "A high-INT caster wins by casting alone, with every gate met, so the gates alone no longer hold it back"
sources:
  - "#278"
  - "#766"
  - "#1235"
  - "docs/adr/legacy-mvp-decisions.md#d-33--spell-power-is-gated-by-four-independent-conditions-not-by-damage-tuning"
  - "entity/spell_book.gd"
  - "systems/battle_system.gd"
tags: [spells, balance, degree, mana, range, design]
---

# ADR 0039 — Spell power is gated by four conditions, not by damage tuning

> **Backfilled 2026-09-30** from [D-33](legacy-mvp-decisions.md#d-33--spell-power-is-gated-by-four-independent-conditions-not-by-damage-tuning), with gate 3 as [D-34](legacy-mvp-decisions.md#d-34--mana-is-int-bought-across-turn-sustain-tempo-gate-3-settled) settled it and #766 later revised it. It is a balance call, and it is recorded because the owner picked it in the #1224 sweep (*"D-18 + D-33 (balance)"*, owner, 2026-09-30).

## Context

D-18 made INT the runaway attribute, and spell damage scaled with it. Something had to stop a high-INT caster from simply winning. Tuning damage down would have cancelled the reason to invest in INT. Mana was the weakest gate at the time: D-34 found it already INT-derived and kept it, and #766 later found that shape never bound at high INT.

## Decision drivers

- A strong spell should land hard. The constraint is *when* it can be cast, not how hard it hits.
- A gate has to be built on the board, not bought with attributes, so positioning stays the play.
- Every attack channel stays a live tool. A caster still takes a cut vertex with a Ranged attack.
- A gate that never blocks, or always blocks, is not worth having.

## Decision

The resolution adopted 2026-08-03 (D-33): **a spell's power is gated by four independent conditions, and damage tuning is not one of them.**

1. **Knowing the spell**: innate in the spellbook, or granted by a node you hold.
2. **Casting degree**: `SpellDef.min_degree`, read as entity degree at the cast-from node. This is the primary gate. Ladder: 1–2 everyday, 3 a deliberate hub, 4 picky, 5+ endgame.
3. **Mana**: cost against pool, a cross-turn tempo. Since #766 the board is the source: *"players will need to be getting mana (regen) from the board instead (procgen-rolled skillnodes)"*, keeping the INT transfers but *"very conservative"* (owner, 2026-09-14).
4. **Range from the cast node**: hop or euclidean reach to eligible primary targets. Gates 2 and 4 pull against each other on purpose: a 6-degree hub far from the enemy casts nothing worth casting.

## Consequences

- Gate 1: `Entity.spellbook` (`entity/entity.gd:98`); `SpellGrant` effects on allocated nodes add and revoke spells (`entity/spell_book.gd:45`, `:62`).
- Gate 2: `SpellBook._node_meets_source_requirements` checks `navigator.get_degree(source) >= min_degree` inside the entity's mirror (`spell_book.gd:125`). Authored values are 2–4 across the 13 defs in `attack/spell/defs/`; unset defs default to 1.
- Gate 3: launch refuses when `mana` is below the cost (`systems/battle_system.gd:637`). Gate 4: `HopRangeFinder` reads `cast_range_hops` (`attack/range_finder/hop_range_finder.gd:46`). Eleven defs are hop-ranged; `cyclone` and `healing_beam` are euclidean.
- Mana, the one per-entity gate, is where caster identity choices concentrate. The other three gates carry the topology.

## Alternatives considered

### Tune spell damage down until INT stops winning
Lost on "a strong spell should land hard". **Ground since weakened:** D-33 leaned on D-18's *linear* damage payoff, and damage now takes √INT (ADR 0038). That was a fix for loot stacking, though, not a gate, so this call still stands. **Most likely to be revived** if a caster who meets all four gates still wins alone.

### Mana as INT-bought sustain tempo (D-34's shape)
**Dead ground.** `10 + INT/10` pool and `log10(INT)` regen never bound past roughly INT 200 (#766). Gate 3 keeps D-34's purpose, cross-turn tempo, but the board is now the source.

### Per-node positional mana bins
Rejected in D-34: the other three gates already carry the topology, and a per-entity pool is deliberately the odd one out.
