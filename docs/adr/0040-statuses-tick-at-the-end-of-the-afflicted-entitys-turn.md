---
id: 0040
title: Statuses tick at the END of the afflicted entity's turn, both hosts in one beat — never at turn start, never per family
status: accepted
date: 2026-09-30
deciders: owner
supersedes: []
superseded-by: null
revisit-when: null
sources:
  - "#1256"
  - "#1255"
  - "#1202"
  - "docs/design/damage_over_time.md"
  - "docs/domain/effect-system.md"
  - "entity/entity.gd"
tags: [combat, status, dot, turn, design]
---

# ADR 0040 — Statuses tick at the end of the afflicted entity's turn

## Context

The entity host ticks, and then the owned-node sweep runs, inside `Entity.begin_turn`, after upkeep and regen and before `turn_began` kicks the controller. That placement was inherited, not decided: `docs/design/damage_over_time.md` listed it as open, and ADR 0024 only recorded it as a consequence. #1202 (sandpile topple) and #1204 (spread) both built on it. The only cures that exist are deallocating a node, which voids its statuses, and moving the core. Turn start already carries upkeep, regen, reload, class hooks and the status sweep.

## Decision drivers

- **Counterplay:** can the victim answer a DoT before its first tick?
- **Fairness:** a poisoned core must never leave its owner with a turn that is only a wait to die.
- **Identity:** a DoT should play as a slow killer, not as a direct hit that arrives late.
- **Turn-start load:** fewer things should resolve at turn start.
- **One beat:** every family ticks at the same moment, so timing needs no tooltip.

## Decision

1. **A status ticks at the end of the afflicted entity's turn, for both hosts.** The entity host ticks first, then the owned-node sweep. The rules carried over from `begin_turn` stay: it runs on every real turn, and never on a resync cursor. Owner, 2026-09-30: *"flip it"*, after naming the grounds: *"if your core gets poisoned (outside of your turn) you'd just be waiting for your turn to start so you can die. there is nothing you can do"*; *"turn start means applying poison is basically guaranteed direct damage just a bit later"*; *"turn end for this might also relieve the many happenings at turn start"*.
2. **A last action before a DoT death is intended, not a cost.** Owner, 2026-09-30: *"last grasp isn't just fine, it's expected. poisons are slow killers, and even a 1 turn delay is slow enough for me, infinitely slower than a 0-turn direct damage death by enemy attack"*.

## Consequences

- Every tick can be answered, the first included. A victim can deallocate or cleanse a poisoned node, or move a poisoned core, before any damage lands. The cure lane (cleanse spells, fountain addons) becomes counterplay instead of cleanup.
- A DoT no longer guarantees its first tick. An attacker who wants damage that can't be answered uses a direct hit. Any "ticks on landing" behaviour is content, not timing.
- Regen at turn start and the DoT at turn end sit at opposite ends of one turn cycle. Over a full cycle the net is unchanged; only who can act between them changes.
- The health-bar projection reads as "if you end your turn now". The end-turn action is the moment the projection comes true.
- A node that will die to a DoT at end of turn can still be used during that turn.
- ADR 0024's consequence line placing entity-host ticks on `_on_turn_started` no longer holds. ADR 0024's decision (two hosts, falling through a cracked core) stands.

## Alternatives considered

### Turn start (the inherited placement)
**Rejected on fairness and counterplay.** A fresh application is guaranteed a tick before the victim can react, and a poisoned core makes the victim's next turn a wait to die. It won on readability (you see the damage, then act) and on genre convention (Slay the Spire, Darkest Dungeon). Neither argument was dismissed; both lost to fairness and counterplay. **The alternative most likely to be revived**, if DoTs prove too weak without a guaranteed tick. Revive it per family through content (a tick on landing) before moving the beat.

### Per-family timing (each `StatusDef` declares its beat)
**Rejected on one beat.** It needs two tick paths for one tick, and players can't predict timing without reading the def.
