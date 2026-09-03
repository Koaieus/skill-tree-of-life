---
description: What gates a procgen StatPool to an archetype — the pool's own archetype_stat, never the pack's or the .tres it lives in
paths:
  - "procgen/pools/**"
  - "procgen/modules/**"
  - "procgen/archetypes/**"
---

# Which nodes can roll a StatPool

**The gate is `StatPool.archetype_stat` (the inner one). `StatPack.archetype_stat` (the
outer one, and the `.tres` filename) is documentation and nothing else.**

`ModifierPoolSet.flatten_for_node()` iterates *every* pack unconditionally and filters
per-pool:

```gdscript
for pack in packs:              # ALL packs, no pack-level check
    for pool in pack.pools:
        if pool.archetype_stat == &"" or pool.archetype_stat == primary_stat:
```

**Why:** the `.tres` files are authoring folders, not scopes. `constitution.tres` deliberately
mixes CON-scoped pools with the universal defensive ones; `intelligence.tres` has carried a
pool scoped to `constitution`. Where a pool *lives* tells you nothing about where it *rolls*.

**How to apply:**

- **`archetype_stat` defaults to `&""`, and `&""` means universal — every node of every
  archetype.** "I forgot to set it" and "I want this everywhere" are the same value. This is
  the trap: #718 shipped a curse on all six archetypes because an edit changed `stat_id` and
  left the never-authored `archetype_stat` alone.
- **A curse/downside pool should carry an explicit `archetype_stat` and empty `tags`.** Tags
  feed `ArchetypeWeightProfile` (multiplies across every matched tag) *and* `ArchetypePolicy.forbid_tags`
  (a brick wall). A stale tag silently relocates a pool's incidence — a `-dexterity` pool still
  tagged `int` got a 3x boost on INT nodes and was banned outright on gold/purple.
- `StatPack._get_configuration_warnings()` flags a pool whose non-empty `archetype_stat`
  disagrees with its pack's. It is `@tool`-only — an inspector triangle nothing headless reads.
  It cannot catch a `&""` pool at all, since universal pools are legal in any pack.
- Changing any pool's `archetype_stat` shifts every downstream weighted-pick index. Regenerate
  the procgen goldens with `mise run procgen-golden-regenerate` and justify the diff.

**This is the current shape, not the settled one.** #751 proposes deleting the inner
`archetype_stat` and making the pack the only gate — rewrite or delete this rule when it lands.
