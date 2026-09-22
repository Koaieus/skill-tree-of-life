---
description: What gates a procgen StatPool to a node — two keys, the pool's own archetype_stat and its own subtypes set; never the pack's or the .tres it lives in
paths:
  - "procgen/pools/**"
  - "procgen/modules/**"
  - "procgen/archetypes/**"
---

# Which nodes can roll a StatPool

**The gate is TWO KEYS, both on the pool itself: `StatPool.archetype_stat` and
`StatPool.subtypes`. `StatPack.archetype_stat` (the outer one, and the `.tres`
filename) is documentation and nothing else.**

`ModifierPoolSet.flatten_for_node()` iterates *every* pack unconditionally and filters
per-pool:

```gdscript
for pack in packs:              # ALL packs, no pack-level check
    for pool in pack.pools:
        if pool.archetype_stat == &"" or pool.archetype_stat == primary_stat:
            if pool.admits_subtype(node_subtype):   # `subtypes` empty = any
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

**This is the current shape, not the settled one.** #751 proposes deleting the inner
`archetype_stat` and making the pack the only gate — rewrite the *archetype* half of this
rule when it lands. **The subtype half survives #751 either way (D8):** a pack is one
archetype by definition, so repeating it is noise, but a pack deliberately holds *mixed*
subtypes, so subtype is real per-pool information and stays on the pool.
