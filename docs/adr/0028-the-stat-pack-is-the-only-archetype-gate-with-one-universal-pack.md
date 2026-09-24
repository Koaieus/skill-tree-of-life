---
id: 0028
title: The StatPack is the only archetype gate, and exactly one pack is universal
status: accepted
date: 2026-09-23
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "a pool genuinely needs to roll on some but not all archetypes (a two-archetype hybrid pool), or universal content needs more than one home"
sources: ["#751", "#718", "#750", "#975", "docs/design/node_subtypes.md decision 8", "procgen/pools/modifier_pool_set.gd"]
tags: [procgen, content, authoring, pools]
---

# ADR 0028 — The StatPack is the only archetype gate, and exactly one pack is universal

## Context

Until #751 a procgen `StatPool` carried its own `archetype_stat`, and that
inner field was the gate; the pack's `archetype_stat` and the `.tres` filename
were documentation. The inner field defaults to `&""`, which means universal,
so "forgot to set it" and "roll this everywhere" were one value spread over
~40 sub-resources. `1aa8f29` shipped a CON curse on all six archetypes that
way. The owner, on finding the gate: "authors should author a stat pack per
archetype … remove the inner archetype, make the outer the only gate"
(2026-09-04). Held back then because movement / deallocation pools would
have had no home.

## Decision drivers

- An author reads a pack as "what this archetype's nodes roll"; the gate
  should say the same.
- The `&""` default trap should live on a handful of named files a test can
  pin, not on every pool.
- Movement, deallocation and the shared defences need a home.
- The universal slice (#975) partitions entries into universal vs archetype
  mass, so the universal/archetype distinction has to survive.

## Decision

**Option A** (owner, 2026-09-23). `StatPool.archetype_stat` is deleted. A pool
rolls on a node iff its **pack's** `archetype_stat` is `&""` or equals the
node's `primary_stat`, and its own `subtypes` admits the node's subtype
(unchanged; subtypes stay per-pool, node_subtypes.md decision 8). `&""` on a
pack means universal, and **exactly one pack is universal**: `universal.tres`
(renamed from `mobility.tres`), which now also holds `armor +` and
`node_health +%` (moved out of `constitution.tres`). `StatPool.to_entries`
takes the pack's archetype to mint the entry id segment, so ids do not move.
`test_pool_scoping.gd::test_every_pack_is_gated_by_its_file_name` pins every
pack's value to its file stem.

This is a firm owner call, not a tentative pick.

## Consequences

- A pool's scope is the file it sits in; there is nothing per-pool to forget.
- `StatPack._get_configuration_warnings`'s inner-vs-outer cross-check is gone
  with the fact it compared.
- Effective scope of every pool is unchanged. The flattened entry **order** is
  not, for CON-primary nodes, because `armor +` / `node_health +%` now come
  after the CON pack's own pools. The weighted pick walks entries in order, so
  the same seed can roll differently on CON nodes (see #751 for how that was
  resolved).
- A seventh archetype is a new pack file with its own `archetype_stat`.

## Alternatives considered

- **B — no universal packs.** Armor / node_health become CON-only, movement /
  dealloc copied into all six packs. Rejected: kills the #975 universal slice
  and duplicates mobility ×6. Dead unless the slice is retired.
- **C — delete the pack field, keep the pool gate.** Rejected: keeps the
  `&""`-default trap on every pool and reverses node_subtypes.md decision 8.
