---
id: 0038
title: INT is the runaway attribute, and every transfer out of it is thinned — spell damage takes √INT, reach and mana take big divisors or saturating ladders; the linear damage payoff and the ×2 reach cap are retired
status: accepted
date: 2026-09-21
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "INT stops being the designed runaway (its procgen pool numbers lose their extra fat), or high-INT magic damage stops reading as a payoff at the top of the range (#760's question)"
sources:
  - "#776"
  - "#766"
  - "#912"
  - "#1234"
  - "docs/adr/legacy-mvp-decisions.md#d-18--int-is-the-runaway-attribute-utility-compresses-damage-does-not"
  - "entity/default_entity_board.tres"
tags: [stats, balance, int, spells, formulas, design]
---

# ADR 0038 — INT is the runaway attribute, and every transfer out of it is thinned

> **Backfilled 2026-09-30** from [D-18](legacy-mvp-decisions.md#d-18--int-is-the-runaway-attribute-utility-compresses-damage-does-not) (2026-07-21). Two of its three legs have since been revised by owner calls, so this record states the call as it stands and is dated to the latest of them. It is a balance call, and it is recorded because the owner picked it in the #1224 sweep (*"D-18 + D-33 (balance)"*, owner, 2026-09-30, recorded on #1234).

## Context

D-18 accepted INT as the runaway attribute, running into the thousands, as one package: utility compresses, reach is hard-capped at ×2 of a spell's reach, and spell damage stays the *linear* payoff so that the runaway means something. Post-LAN play (2026-09-07) then showed that every "+1 X per Y" intrinsic ran away once it was looted and stacked (#776). Mana never bound at high INT (#766). And cast range was re-cut into two bin-decomposed stats over the spell's authored reach (#912, #1018).

## Decision drivers

- INT alone is designed to run away; the other attributes should not.
- One copy of an intrinsic is thin, and stacking copies is how a player specialises (#776).
- Reach is the dangerous axis, because the area a spell covers grows faster than its radius.

## Decision

- *"Int is designed with extra fat procgen numbers so designed to be a runaway primary attribute. The others less so."* (owner, 2026-09-13, #776)
- *"The knee is not intuitive. possibly we drop it in favor of a pure sqrt relationship."* That applies to spell damage only; spell range and max mana get *"raised divisors"* (owner, 2026-09-13, #776).
- On mana's two innate transfers: *"Keep both, very conservative."* (owner, 2026-09-14, #766)
- Cast range is the spell's authored reach plus bins, with the INT hop ladder in ADD_BASE (owner decisions, 2026-09-21, #912).

## Consequences

- `spell_damage` takes `SqrtFormula` on INT (`entity/default_entity_board.tres:417`; def `stats_system/defs/spell_damage.tres`). It is unbounded but sublinear.
- Reach: `cast_range_distance` gains +1% increased per 50 INT (`default_entity_board.tres:383`). `cast_range_hops` is a saturating ladder, +1 at 50/150/500/1000/5000 INT (`:395`). Both stats are defined in `stats_system/defs/`.
- Mana: +1 max per 1000 INT (`:316`) and +1 regen per tenfold of INT (`:327`). The board, not INT, is the mana source.
- The combined runaway stays survivable because every leg compresses. None of them is a flat cap.

## Alternatives considered

### D-18 as written: utility compressed, damage the linear payoff
**Dead grounds:** "spell damage is the linear payoff". The owner replaced the ratio with √INT in #776, because a looted second copy doubled an already-working rate. D-18's "44× board impact" arithmetic assumed linear damage and no longer describes the game. **Most likely to be revived** if √INT damage reads as no payoff at high INT (#760).

### Clamp reach at ×2 (`spell_range = clamp(INT/10, 0, 100)`)
Never built. Lost on "one copy thin, stacking specialises": a hard clamp stops looted copies from ever adding reach. The divisor went to 50 instead, and hops moved to a saturating ladder. **Dead ground:** the `spell_range` stat is gone (#1018).

### Bonus hops added after the multiplier
D-18 rejected ADD_BASE hops because INT's reach percent would amplify a found +1 hop into +2. **Dead ground:** INT's percent now applies to distance only (#912), so no INT term multiplies hops. #912 put the INT hop ladder in ADD_BASE on purpose: ladder hops scale with any hop percent a player stacks, and that is intended.

### D-18's mana shape (`INT/10` pool, log regen as the gate)
Lost on "INT alone runs away" colliding with a mana pool that never binds (#766). Both innate transfers survive only as token amounts.
