---
id: 0079
title: Resolution always runs on a CombatWorld.shadow(), and the world is a required parameter, never a defaulted one
status: accepted
date: 2026-08-23
deciders: owner
supersedes: []
superseded-by: null
revisit-when: null
sources:
  - "#536"
  - "docs/domain/attack-timeline.md"
  - "combat/combat_world.gd"
tags: [combat, multiplayer, architecture]
---

# ADR 0079 — resolution always runs on a shadow; the world is required

Backfill, recorded 2026-11-08: the call is quoted in `attack-timeline.md`
since it was made; ADR 0011's consequences gesture at it without recording it.

## Context
Magic gates during candidate selection (wave N+1's filter must see wave N's
kill), so resolution itself mutates state; melee and ranged gate at
consumption. Previews, AI scoring and validation all need to resolve without
touching the real world, and ADR 0011 had just fixed one timeline contract for
every mode.

## Decision drivers
- No "simulation" flag, no suppressed side effects, no special-cased preview caller.
- The sim path and the real path must agree by construction, not by discipline.
- One rule that covers all three attack modes.

## Decision
"Every resolution runs on a `CombatWorld.shadow()`, and the real world is
mutated only by `OutcomeApplier` landing a rebuilt record" — owner call,
2026-08-23: "shadow always". And "the world is a required parameter, never a
defaulted one" (owner call, 2026-08-23); same rule on
`BladePopResolver.LiveGate.admit`.

## Consequences
Buys: nothing needs suppressing, no preview is a special case, and `_validate`
may legally resolve (shadow-only) to produce the very record it gates on.
Costs: every caller must say which world it means, and `_validate` is not
side-effect-free in the pure-query sense — it must be read as "the command is
final and legal, or it is refused".

## Alternatives considered
### world = null defaults to the live world
Lost on the second driver: an implicit live branch inside `OutcomeApplier`
turns "the sim and the real path agree by construction" back into "by
discipline"; one forgotten argument mutates the real world from a preview.
### A simulation flag on the resolvers
Lost on the first driver: every mutating site must check it, and a missed
check is invisible until a preview corrupts live state.
