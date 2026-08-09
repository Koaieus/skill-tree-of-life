# Stat board classes — the #332 three-class split

Why `StatBoard` holds no stats, why `EntityStatBoard` and `NodeStatBoard` are
siblings rather than a chain, and why node boards bake some stats and stay
sparse for the rest. The one-screen version lives in
`.claude/rules/stats-system.md` under "Board classes"; this is the reasoning and
the measurements behind it.

## Three board classes: mechanism base + Entity/Node siblings (#332)

`StatBoard` holds **no stat fields at all** — it is lookup, modifier routing, binding, the cycle gate, and the introspection walks. Two **siblings** carry the stats:

| Class | Holds |
|---|---|
| `EntityStatBoard` | every stat an entity can possess, as typed `@export` fields (`entity/default_entity_board.tres`) |
| `NodeStatBoard` | node-**owned** stats baked as typed fields (`skill_node/default_node_board.tres`); borrowed ones sparse |

**Siblings, not a chain.** A node board is not a specialization of an entity board; inheriting ~40 permanently-null entity fields onto every one of a level's 500–2500 SkillNodes is the shape the split exists to avoid. The base keeps the name `StatBoard`, so every function taking a board (`StatFormula.compute`, `Mitigation.apply`, the visualizer, `SkillNode._contribution_board`) is unchanged and polymorphic.

**Why inheritance and not an array of sub-boards.** The existing mechanism *is* `get_property_list()` introspection — `collect_formula_edges`, `get_pool_stats` and `get_stat_ids` discover a subclass's fields for free. Sub-boards would mean reimplementing discovery in `get_stat`, both walks, `bind_modifier`/`unbind_modifier` and `stat_board_graph.load_board`, and their one upside (authoring a shared group once) does not apply: node boards resolve shared ids dynamically through `StatRegistry`, never as fields.

### `_mint_stat` is the subclass seam; `_ensure_stat` is the gate above it

`_ensure_stat` owns the accessor-token rejection and the already-exists short-circuit, then delegates to `_mint_stat(id)` — so no subclass can forget the gate.

- `StatBoard._mint_stat` — mints from `StatRegistry` into `_extra_stats` (the sparse default).
- `EntityStatBoard._mint_stat` — **refuses, with a warning.** An entity board declares every stat it can hold, so a mint attempt is a typo in a modifier's `stat_id` (or a node-only id aimed at the wrong board). The rule is derived from the class shape, **not an authored deny-list**, so it cannot drift.
- `NodeStatBoard._mint_stat` — one exception: `node_health` becomes a **`PoolStat` built from the `node_combat_health` def**, because the entity board's `node_health` is the ScalarStat *baseline*. Same id, different Stat class per board. This used to be a hardcoded branch in `SkillNode._ensure_local_stat` writing straight into `node_board._extra_stats`.

**No mirror guard on `NodeStatBoard`, deliberately.** An entity-only stat minted on a node board is *inert*, not wrong (a node-local `strength` modifier is simply never read), and rejecting it would require authoring "stats that mean nothing on a node" — a design statement (#287's `StatDef` scope enum), not a mechanism. Both leak directions are equally harmless; only the entity one is free to close.

### Bake what the node owns; stay sparse for what it borrows

This line is **forced by the read path**, not chosen for taste. `get_local_value` merges an owned node as `ModifierBins.compute(entity_stat.base_value, [entity.bins, node.bins])` — for any id the entity *also* carries, the node-board stat's own `base_value` is **silently discarded** and only its bins count. Authoring `armor = 5` on a node board does nothing, with no error.

- **Owned** (nothing on the entity board shadows the id): `stake_level` (PoolStat, cap = stake / current = allocation level) and `addon_slots`. Baked as typed fields with live authored `base_value`, plus the `addon_slots = base(0) + allocation_level` formula as a template **intrinsic** (`node_board.apply_intrinsics()` runs in `SkillNode._init_node_board`). Nothing is built in code any more — `_mint_stake_pool` / `_mint_addon_slots` are gone.
- **Borrowed** (`armor`, `min_damage_taken`, `node_healing`, `blade_damage`, `node_health`, …): mint-on-demand. Nothing to author, so a field would buy nothing and cost one Stat per node. `node_health` is on this side despite being the node's own combat pool — the entity carries that id as the baseline, so it is shadowed.

### `get_stat_ids()` vs `get_dynamic_stat_ids()` — promoting a stat to a field drops it from the latter

`get_dynamic_stat_ids()` reads `_extra_stats` **only**. So baking a stat silently removes it from that answer, and `ui/tooltip_fan/panels/node_stats_panel.gd` enumerated the node board through exactly it. `get_stat_ids()` (non-null typed fields **plus** minted ones) is what a "what's on this board" UI wants. Use it for display; `get_dynamic_stat_ids()` only when you specifically mean "what got minted" (the sparseness assertions in `test_node_local_bind.gd` / `test_addon_slots.gd` do).

### `SkillNode.node_board` is a deep clone and is NOT `@export`ed

`_init_node_board()` does `DEFAULT_NODE_BOARD.duplicate(true)`, mirroring `Entity._ready`. Lazy — a node that needs nothing allocates nothing.

- **Deep clone, not `resource_local_to_scene` on the template.** That flag does **not recurse into sub-resources**; each baked Stat would need it individually, or every SkillNode in the level shares one set of Stat instances and every local modifier applies globally. The Entity pattern has no such discipline to remember.
- **Not exported**, because the board is derived (template clone + runtime mints). Once it carries real Stat sub-resources an `@export` would serialize a full board into every `.tscn` holding a SkillNode on each editor save — the derived-value-writeback hazard, multiplied by the node count. Author `stake_level` / `allocation_level` through their SkillNode-scope proxy properties. A stale `node_board = SubResource(...)` in an unmigrated scene resolves to no property, so the migration is self-healing.

**Measured cost at level scale (2500 nodes, RX 7900 XTX / CPU-bound):** old mint path 19.5 ms, new clone path 172.5 ms — **+153 ms** one-time at generation. Breakdown: `duplicate(true)` 63 ms, `apply_intrinsics` 96 ms, pushes 14 ms. The dominant term inside `apply_intrinsics` is **`cycle_from` → `collect_formula_edges` → `get_property_list()`, 27 ms of it in `get_property_list()` alone** (~11 µs per call, purely to enumerate properties). Caching Stat-valued property names per board *class* in a static would recover most of it and speed up the entity-board paths too — **not done, no issue filed yet.** Don't re-measure from scratch; re-measure the fix.

