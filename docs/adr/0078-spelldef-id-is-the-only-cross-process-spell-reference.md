---
id: 0078
title: SpellDef.id is the only cross-process spell reference — a wire name, never a resource path
status: accepted
date: 2026-08-21
deciders: owner
supersedes: []
superseded-by: null
revisit-when: null
sources:
  - "#511"
  - "docs/domain/multiplayer-sync-model.md"
  - "docs/domain/snapshot-encoding.md"
tags: [multiplayer, netcode, spells, architecture]
---

# ADR 0078 — SpellDef.id is the only cross-process spell reference

Backfill, recorded 2026-11-08: settled alongside #511's wire forks
(2026-08-21) and lived in code comments, then sync-model prose.

## Context
Spell defs are authored `.tres` resources, but what an entity actually holds is
a deep copy (`Entity._ready` duplicates its book so no two entities share the
authored object), and a `duplicate()` has no `resource_path`. Snapshots and
commands still need to name a spell across the wire.

## Decision drivers
- A wire name must survive duplication; a `resource_path` does not.
- Nothing received off the wire may be `load()`-ed as a path.
- `SpellDef` identity comparisons need the one const def, not copies.

## Decision
A spell crosses the wire as `SpellDef.id` and nothing else; ids resolve through
`SpellCatalog.by_id`. Ids are interned into a `spells` table beside `res`,
separate from it "because a `SpellDef.id` is a wire name and not a path
`_load_interned` may `load()`" (2026-08-21).

## Consequences
Buys: rebuilt books hold the const defs the catalog returns, so identity
comparisons work; the decode path can never be steered into loading an
arbitrary resource path. Costs: every spell must be registered in
`SpellCatalog`, and an unregistered def is unreachable across processes by
construction.

## Alternatives considered
### resource_path as the wire reference
Lost on the first two drivers: live books are duplicates with no path, and a
path off the wire invites `load()` of attacker-controlled strings.
### Serialising the SpellDef by value
Lost on identity: copies break `SpellDef` comparisons (#511) and bloat
snapshots for data both sides already have.
