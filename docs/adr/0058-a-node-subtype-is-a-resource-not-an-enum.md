---
id: 0058
title: A node subtype is a `NodeSubtype` Resource carrying its own data (tint, emissive tier, name), not an enum or a bare StringName
status: accepted
date: 2026-10-12
deciders: owner
supersedes: []
superseded-by: null
revisit-when: null
sources:
  - "#1320"
  - "docs/design/node_subtypes.md@179054c"
  - "docs/domain/node-subtypes.md"
  - "procgen/subtypes/node_subtype.gd"
  - "archetypes/archetype.gd"
tags: [procgen, content, authoring, visuals]
---

# ADR 0058 — A node subtype is a Resource, not an enum

> **Backfill.** The decision was made in the node-subtypes design (`docs/design/node_subtypes.md@179054c`, § ① Membership) and shipped with `NodeSubtype`; the owner ratified it as an ADR on 2026-10-12 (#1320).

## Context

A node has a second identity orthogonal to its `Archetype`: `regular`, `blight` or `bless` — archetype picks the family, subtype picks the pole. Subtype crosses three layers: procgen selects on it, `SkillNode` carries it, the visuals read it. The visuals need *data* from it — a tint, an emissive tier, a display name. `Archetype` already had exactly this shape as a `Resource` (`id`, `primary_stat`, `carve_shape`, a derived colour), so subtype had a peer to mirror.

## Decision drivers

- **Carries data:** what crosses the layers must hold the tint, emissive tier and name itself.
- **One edit per new subtype:** adding a pole is authoring one `.tres`, not editing every layer.
- **Peer symmetry:** subtype is `Archetype`'s peer and should read the same way.

## Decision

**A node subtype is a `NodeSubtype` Resource, not an enum or a bare `StringName`.** Owner, 2026-10-12 (#1320), ratifying the design.

- `NodeSubtype` (`procgen/subtypes/node_subtype.gd`) holds a stable `id` plus its data; `regular.tres`, `blight.tres` and `bless.tres` are the instances, and `regular` is the default every node falls back to.
- Which pools a subtype may draw is gated on the pool (`StatPool.subtypes`), not on the subtype.

## Consequences

- The visuals read the tint and emissive tier straight off the subtype; no layer holds a `match`.
- A new subtype is a new `.tres`; the layers that consume it do not change.
- Identity comparisons go through `id` (a `StringName`), so a subtype is still addressable by name where data is not needed.
- A Resource referencing its own class at class scope is a cyclic load: the default is a lazy static accessor, never a `const` preload.

## Alternatives considered

### An enum
**Rejected on one-edit-per-new-subtype and carries-data.** An enum carries no data, so each of the three layers grows a `match` to map it to a tint, a tier or a name, and a new subtype means editing all three. *The alternative most likely to be revived* — by someone wanting an exhaustive `match`; the cost is still three layers per pole.

### A bare `StringName`
**Rejected on carries-data.** It is a usable identity, and is kept as `NodeSubtype.id`, but it cannot hold the tint or tier, so the data would live in a lookup table beside it — an enum's `match` by another name.
