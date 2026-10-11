---
id: 0054
title: A concept's per-role entity stats are declared by their StatDef (a role next to its identity) and minted by the entity board at init, never hand-declared as typed fields
status: accepted
date: 2026-10-11
deciders: owner+agent
supersedes: []
superseded-by: null
revisit-when: "production code wants a statically typed read of one concept's stat that the typed facet door cannot give"
sources:
  - "#1558"
  - "docs/domain/stat-board-classes.md"
  - "stats_system/entity_stat_board.gd"
  - "stats_system/stat_def.gd"
tags: [stats, aspects, architecture]
---

# ADR 0054 — Concept stats are def-declared and minted at init

## Context
Every aspect-matrix concept carries up to three entity stats — `<concept>_aspect`
(supply), `<concept>_stacks_per_hit` (potency), `<concept>_resistance` (defence) —
three roles kept as three stats (owner 2026-10-01, ADR 0029). `EntityStatBoard`
refused to mint, so each stat was four hand-written places: def `.tres`, board
export field, roster row, default-board sub-resource — 26 stats over twelve
concepts, ragged (12 aspects, 9 stacks, 5 resistances). Production read none
through the typed field: every read went through `get_stat` with an id carried
by data; the 29 typed reads were all tests. `stats_system` ranks below
`aspects`, so the board cannot read the aspect roster.

## Decision drivers
- One owner per fact: what a stat is lives on its `StatDef`, nowhere twice.
- Adding a concept must not touch the board script or the board `.tres`.
- The mint refusal that catches a typo'd or node-only id stays.
- A typed read where one is wanted, without a per-concept field.
- Module tiers: the board learns nothing from `aspects/`.

## Decision
Owner, 2026-10-11, choosing between the options on #1558: **"Def-declared,
minted at init."** A `StatDef` carries a `role` (`ASPECT` / `STACKS_PER_HIT` /
`RESISTANCE`, default none) beside its `identity`; `EntityStatBoard` mints every
role-bearing registered def eagerly in `apply_intrinsics`, and still refuses
every other mint. `StatBoard.facet(concept, role)` is the typed door.

## Consequences
Buys: a concept's stats are a def and a roster row; 26 board fields and their
board sub-resources go; the def's `default_value` is the one base value; the
concept→stat edge is derivable from identity plus role. Costs: these stats join
`_extra_stats`, so a test reads them through `facet` or `get_stat`; the eager
mint runs once per entity board at init; sparse boards skip it and stay sparse.

## Alternatives considered
**Typed `ConceptStats` sub-resource per concept** — `board.concepts.poison.aspect`.
Lost on "adding a concept touches nothing on the board": it stays typed only as
a declared field per concept, one level down, and every board walk learns a
nested shape. Most likely to be revived if the revisit condition fires.

**Keep the hand declarations plus a guard test.** Lost on one owner per fact:
the four-place shotgun stays and compounds per concept.

**Mint from the aspect roster.** Lost on module tiers; the defs already carry the fact.
