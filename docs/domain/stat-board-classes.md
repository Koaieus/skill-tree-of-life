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

**Siblings, not a chain.** A node board is not a specialization of an entity board; inheriting ~40 permanently-null entity fields onto every one of a level's 500–2500 SkillNodes is the shape the split exists to avoid. The base keeps the name `StatBoard`, so every function taking a board (`StatFormula.compute`, `Mitigation.apply`, the visualizer, `LocalScaleMutator._contribution_board`) is unchanged and polymorphic.

**Why inheritance and not an array of sub-boards.** The existing mechanism *is* `get_property_list()` introspection — `collect_formula_edges`, `get_pool_stats` and `get_stat_ids` discover a subclass's fields for free. Sub-boards would mean reimplementing discovery in `get_stat`, both walks, `bind_modifier`/`unbind_modifier` and `addons/stat_board_visualizer/stat_board_graph.gd`'s `load_board`, and their one upside (authoring a shared group once) does not apply: node boards resolve shared ids dynamically through `StatRegistry`, never as fields.

### `_mint_stat` is the subclass seam; `_ensure_stat` is the gate above it

`_ensure_stat` owns the accessor-token rejection and the already-exists short-circuit, then delegates to `_mint_stat(id)` — so no subclass can forget the gate.

- `StatBoard._mint_stat` — mints from `StatRegistry` into `_extra_stats` (the sparse default).
- `EntityStatBoard._mint_stat` — **refuses, with a warning.** An entity board declares every stat it can hold, so a mint attempt is a typo in a modifier's `stat_id` (or a node-only id aimed at the wrong board). The rule is derived from the class shape, **not an authored deny-list**, so it cannot drift.
- `NodeStatBoard._mint_stat` — two exceptions, `node_health` and `spikes` (`POOL_DEFS` in `stats_system/node_stat_board.gd`): each becomes a **`PoolStat` built from a separate def** (`node_combat_health`, `node_spikes`), because the entity board's ids are ScalarStat *baselines*. Same id, different Stat class per board.

**No mirror guard on `NodeStatBoard`, deliberately.** An entity-only stat minted on a node board is *inert*, not wrong (a node-local `strength` modifier is simply never read), and rejecting it would require authoring "stats that mean nothing on a node" — a design statement (#287's `StatDef` scope enum), not a mechanism. Both leak directions are equally harmless; only the entity one is free to close.

### Bake what the node owns; stay sparse for what it borrows

This line is **forced by the read path**, not chosen for taste. `get_local_value` merges an owned node as `ModifierBins.compute(entity_stat.base_value, [entity.bins, node.bins])` — for any id the entity *also* carries, the node-board stat's own `base_value` is **silently discarded** and only its bins count. Authoring `armor = 5` on a node board does nothing, with no error.

- **Owned** (nothing on the entity board shadows the id): `stake_level` (PoolStat, cap = stake / current = allocation level) and `addon_slots`. Baked as typed fields with live authored `base_value`, plus the `addon_slots = base(0) + allocation_level` formula as a template **intrinsic** (`node_board.apply_intrinsics()` runs in `SkillNode._init_node_board`).
- **Borrowed** (`armor`, `min_damage_taken`, `node_healing`, `blade_damage`, `node_health`, …): mint-on-demand. Nothing to author, so a field would buy nothing and cost one Stat per node. `node_health` is on this side despite being the node's own combat pool — the entity carries that id as the baseline, so it is shadowed.

### `get_stat_ids()` vs `get_dynamic_stat_ids()` — promoting a stat to a field drops it from the latter

`get_dynamic_stat_ids()` reads `_extra_stats` **only**. So baking a stat silently removes it from that answer, and `ui/tooltip_fan/panels/node_stats_panel.gd` enumerates the node board. `get_stat_ids()` (non-null typed fields **plus** minted ones) is what a "what's on this board" UI wants. Use it for display; `get_dynamic_stat_ids()` only when you specifically mean "what got minted" (the sparseness assertions in `test_addon_slots.gd` do).

### `SkillNode.node_board` is `@export`ed, scene-composable, and cloned once

`_init_node_board()` deep-clones the authored board (the scene wires `default_node_board.tres`) or the template, exactly like `Entity._ready`. Lazy — a node that needs nothing never pays for a clone.

**Exporting it is safe.** The derived-value-writeback hazard needs a *transforming* function: the editor serializes the computed value, the next load computes again from there, and it compounds. `duplicate(true)` is **idempotent** — a deep copy round-trips to the same values — so writing the clone back into the export is stable. `Entity` does the same. A level, cluster or single node should be able to compose its own board, and a saved level should serialize real per-node stat state.

**Deep clone, not `resource_local_to_scene` on the template.** That flag does **not recurse into sub-resources**; each baked Stat would need it individually, or every SkillNode in the level would share one set of Stat instances and every local modifier would apply globally. The Entity pattern has no such discipline to remember.

**The real hazard is conflating *authored* with *initialized*.** `if node_board != null: return` means a scene-authored board never gets `apply_intrinsics()` — a correct-looking board with a dead `addon_slots` formula and no error anywhere. `_node_board_ready` is the initialization flag; `node_board`'s setter resets it, because assigning the property means "here is the authored board" and must force a re-clone. That also keeps `fan_live_sandbox.gd`'s `node_board = null` idiom working for a board-less node. Every read path gates on the flag, never on non-null — otherwise it would read or mutate the *shared* authored template, which is reachable now that the scene wires one.

**Cost at level scale (2500 nodes, CPU-bound):** about 100 ms one-time at generation (`duplicate(true)` ~50 ms, `apply_intrinsics` ~44 ms). This is a **worst case**: the bench forces `_init_node_board()` on all 2500, whereas the board is lazy and only materializes for nodes that take a local modifier or get allocated.

The `addon_slots` formula is **file-backed** (`stats_system/formulas/stake_scaling.tres`), not inline, so `duplicate(true)` shares one instance across every board instead of forking the curve 2500 ways — the `level_scaling.tres` contract, pinned by `test_stake_scaling_formula_is_shared_across_every_node_board`. Inlining it would fork the curve per board and break shared retuning silently. The **modifier** stays inline/per-board on purpose: it is the reactive subscriber, and one shared instance would make a single node's allocation change recompute `addon_slots` on every node in the level.

**The `get_property_list()` walk is cached per board class.** `StatBoard._stat_property_names()` caches the declared Stat-typed field names in a `static var` keyed by `get_script()` (a board *class* fact — see its docstring for why the key can't be "which fields are non-null on the first instance seen"); `collect_formula_edges`, `get_pool_stats` and `get_stat_ids` all share it. Without it `apply_intrinsics` roughly doubles.

### Cloning a *live* board (`clone_live`)

`duplicate(true)` clones a **virgin template**; `StatBoard.clone_live()` clones an already-modified board (the combat shadow's need). Exports-only copying would leave every `Stat.bins` empty and drop `_extra_stats` (every minted stat, `node_health` among them) with no error.

- **A bin tally is only meaningful next to the `_modifiers` list it was folded from.** `Stat.add_modifier` ends in `_resync_bins_if_trivial()`, which rebuilds the bins from `_modifiers` when that list holds 0 or 1 entries, so a bins-only copy is correct until the first mutation. `Stat.adopt_modifier_list(src)` carries `_modifiers` and `_last_contrib` one level deep (shared instances are safe: a modifier is stateless and may live on N boards). Pinned by `test/unit/test_stat_board_clone_live.gd`.
- **Formula-bearing modifiers are localized per clone.** Re-binding the shared instances is wrong: the clone's `value_changed` would `emit_changed()` on an instance the **live** board is subscribed to (notification storms on the real world), and the connected `Callable` would keep every shadow `Stat` alive for as long as the shared modifier. `clone_live` sets `StatBoard._is_clone`; from then on every formula-bearing modifier admitted to that board is replaced by a private copy — at clone time by `Stat.localize_formula_modifiers`, afterwards by `add_modifier`. Static modifiers stay shared and unsubscribed (a shadow is a frozen world plus its own mutations).
- **`StatBoard._localized` maps `original → copy`** and `remove_modifier` translates through it, so the handle a caller already holds is the handle that works. Aliases chain across clones of clones.
- **Localize after the whole ensure/copy pass, never inline.** `bind_modifier` resolves each formula input via `dst.get_stat(id)`; a source stat the clone has not minted yet yields a `push_warning` and a silently absent binding.
- **`Stat._modifiers` is swapped everywhere it is keyed by identity** (`_modifiers`, `_last_contrib`, `bins.multipliers`, `bins.winning_set`); a miss gives a modifier that cannot be revoked, invisibly.

### A dropped clone is never collected — `release()` is mandatory

The cycle is `StatBoard` → its `Stat`s → `Stat._board` / `bins.board` → back to the board, and `RefCounted` has no cycle collector. A dropped `clone_live()` result leaks ~120 objects (`Performance.OBJECT_COUNT`); `release()` brings that to 0. The cause is the backpointers, not the localized modifiers' `changed` connections.

`StatBoard.release()` nulls `_board` / `bins.board` across the board's stats, and `EntityCombat.free_shadow()` calls it for the entity board **and every owned node's board**, before it clears `_owned` (the only order that can still reach them).

- **It refuses a live board.** An `Entity`'s board is freed with the entity.
- **A released board is inert, not blank.** `release()` also unbinds the localized copies and drops each stat's modifier subscriptions. `_modifiers` and `bins` are left alone; clearing the list would trip `_resync_bins_if_trivial`'s wipe.

### Cost

The cost of `clone_live` is `Resource.duplicate(true)` and nothing else: the bin copy does not register on a microsecond timer (a clone copies the fold, it never replays the modifiers), so there is no bin-copy optimisation to find. Order of magnitude: entity board ~0.4 ms, node board ~30 µs, one `EntityCombat.snapshot()` + `free_shadow()` at 200 owned about 10 ms (~1.5 frames at 144 Hz, ~83% board cloning). Affordable for melee (`AiBladeRollout` promotes 3 finalists); not for exhaustive ranged/magic candidate enumeration. The lever if it bites: `ModifierBins.compute` is already N-source, so a slice can compose `[live.bins, …, overlay.bins]` and copy nothing. Rerun `test/perf/bench_combat_snapshot.gd` for current numbers.
