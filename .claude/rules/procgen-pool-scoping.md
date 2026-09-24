---
description: What gates a procgen StatPool to a node — two keys, the pack's archetype_stat (the file it lives in) and the pool's own subtypes set
paths:
  - "procgen/pools/**"
  - "procgen/modules/**"
  - "procgen/archetypes/**"
---

# Which nodes can roll a StatPool

**The gate is TWO KEYS: the pack's `StatPack.archetype_stat` (a pool rolls where its
file says) and the pool's own `StatPool.subtypes`.** Pools carry no archetype (ADR 0028).

```gdscript
for pack in packs:
    if pack.archetype_stat != &"" and pack.archetype_stat != primary_stat: continue
    for pool in pack.pools:
        if pool.admits_subtype(node_subtype):   # `subtypes` empty = any
```

**How to apply:**

- **A pool goes in its archetype's pack; shared content goes in `universal.tres`**, the one
  pack with `archetype_stat = &""`. `&""` is also the field's default, so a new pack that
  forgets it reads as universal — `test_pool_scoping.gd` pins every pack to its file stem.
- **A curse/downside pool carries empty `tags`.** Tags feed `ArchetypeWeightProfile`
  (multiplies across every matched tag) *and* `ArchetypePolicy.forbid_tags` (a brick wall).
  A stale tag silently relocates a pool's incidence — a `-dexterity` pool still tagged `int`
  got a 3x boost on INT nodes.
- **Moving a pool between packs changes the flattened entry order**, and the weighted pick
  walks that order — the same seed rolls differently, so the procgen goldens go red even
  when every pool's scope is unchanged. Regenerate only deliberately: flip `_REGENERATE` in
  `test/unit/procgen/test_preset_generation_golden.gd` (its header has the steps) and
  justify the diff.

**The second key — `subtypes` (#1056).** `Array[NodeSubtype]`, **empty = any subtype**,
which is the attribute ladder and most content; the eight flavour pools gated by #1059
(the four DoT potencies blighted, the four resistances blessed) are the exceptions. A non-empty list is BOTH the membership gate and the
give-up: a pool authored `[regular, bless]` is one a blighted node cannot draw, which is
how "blighted DEX trades crit% for DoT stats" is stated per-archetype with no second
mechanism. There is no `NodeSubtype.forbid_tags` — the set IS the give-up (D12).
`ArchetypePolicy.forbid_tags` is the *archetype's* give-up and is unrelated.

- **Match by `NodeSubtype.id`, never by object identity** — `StatPool.admits_subtype` is
  the only place that comparison lives. A config reached through `duplicate(true)` (the
  golden fixture, `test_pool_scoping`) holds *copies* of its subtype resources, and the
  copy is the same subtype.
- **A non-empty `subtypes` appends a sorted id segment to every entry id**
  (`<stat>_<op>_<arch>_s<ids>_t<tier>`), because two pools for the same (stat, op,
  archetype) gated to different subtypes would otherwise collide and weight profiles
  target by that id. An empty list appends nothing, so an ungated pool's id never moves — the eight pools
  gated by #1059 did gain the segment, which is what their golden churn was.
- **Leave a pool shared by every subtype at `[]`** (decision 16) — never copy it per
  subtype. Authoring discipline, deliberately not enforced in code: copy a pool to
  `[regular, bless]`, forget `[blight]`, and blighted nodes silently lose that content
  with no symptom. D13's demotion does **not** catch it, because the node still stands on
  its other pools.
- **D13, the demotion:** a rolled subtype stands only if some *reachable* pool NAMES it
  (`GraphProcgen._build_subtype_drawability`, computed once per `generate()`). An ungated
  `[]` pool deliberately does not count — it is drawn by everyone, so counting it would
  let a node look blighted and play regular.

Full model and the decision list: `docs/design/node_subtypes.md`.

**The subtype half stays per-pool (D8):** a pack is one archetype by definition, so the
archetype lives on the pack; a pack deliberately holds *mixed* subtypes, so subtype is real
per-pool information.
