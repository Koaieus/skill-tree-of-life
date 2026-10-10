---
description: Stat system quick-reference — pipeline, stat IDs (grep), intrinsic scaling, gotchas
paths:
  - "stats_system/**"
  - "entity/default_entity_board.tres"
  - "docs/domain/stat-surfaces.md"
---

# Stat system gotchas

Reference, in three docs: pools, parent/local stats, packs, levels, batching, wire form, visualizer — **`docs/domain/stats-system.md`**; intrinsic-scaling tables and formula classes — **`docs/domain/stat-formulas.md`**; turn-start upkeep, mitigation, DoT and healing — **`docs/domain/stat-upkeep-and-combat.md`**. Adding a tuning knob or pool bin: `docs/domain/stat-knobs-and-bins.md`. Which stat shows where in the HUD: `docs/domain/stat-surfaces.md`. **Keep the doc current** when the stat system changes.

Stat IDs: `grep -h "^id = " stats_system/defs/*.tres | sort`. Mana and mana regen are retired (ADR 0045); restore from tag `retired/mana`, never re-add ad hoc.

## Modifier pipeline

`(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`

- **SET** short-circuits everything; highest `priority` wins, last-in breaks ties; an equal-priority conflict with different values is an authoring error (`push_error`). List order is obtain order and any rebuild must preserve it (`Stat._resequence`). Class-identity SETs (`pacifist_core.tres`) author `priority = 100` so they sit above node/keystone/addon SETs (default 0).
- **INCREASE** sums additively: five +20% = ×2.0, not (1.2)⁵.
- **The merged pipeline is a value, never re-summed.** `ModifierBins.resolve(sources) -> FoldTerms` is the one door to "what the fold is"; `compute` is `resolve().fold(base)`, `Stat.resolve_with(overlays)` is `get_value_with`'s pipeline as a value, `FoldTerms.describe("X")` renders it. **Why:** a MULTIPLY bound to a formula only means something on its own source's board, so a readout that concatenated multiplier lists would print the static coefficient. **How to apply:** a readout asks for a `FoldTerms` and formats it; the arithmetic lives once in `FoldTerms.arith`.
- **Op → bin placement has one home: `ModifierBins.add(m, board)`.** `Stat.add_modifier` and anything building overlay bins route through it; never a hand-rolled `match m.operation` elsewhere.
- **Coercion happens once, at the end, and it is the stat's** (`Stat._coerce`, ADR 0016): INT floors its finished total toward zero (`10.5 → 10`, `-2.6 → -2`), FLOAT passes through, BOOL is `v != 0.0`. **Why:** the floor sits after the bins so `% increased` on a ratio target yields `+1 +1 +1` rather than a burst. **How to apply:** never `roundi`/`floor` inside a formula or modifier; a test wanting an exact integer picks a non-fractional fixture. A pool's `available()` rounds its own `current`, and display formatting keeps its `roundi`.

## Board classes

`StatBoard` holds no stat fields (lookup, routing, binding, the cycle gate, introspection). Siblings `EntityStatBoard` (typed `@export` fields, `entity/default_entity_board.tres`) and `NodeStatBoard` (node-owned stats baked, borrowed sparse, `skill_node/default_node_board.tres`) carry the stats. Five things fail silently:

- **Bake what the node owns; stay sparse for what it borrows.** `get_local_value` merges `ModifierBins.compute(entity_stat.base_value, [entity.bins, node.bins])`, so for any id the entity also carries the node stat's own `base_value` is discarded — `armor = 5` on a node board does nothing, no error. Node-owned and baked: `stake_level`, `addon_slots`, `arrows_per_reload`, `max_shots_per_leaf` (the last two only so their MULTIPLY intrinsics have a non-minting target; `base_value` stays inert). `node_health` is borrowed.
- **`get_dynamic_stat_ids()` reads `_extra_stats` only** — promoting a stat to a typed field drops it. Display code wants `get_stat_ids()`.
- **A sparse stat does not exist until minted, so `get_stat(id)` is `null` at ready time — subscribe via `StatBoard.stat_created(id, stat)`, never poll.** It fires once per id from the single writer `StatBoard._register_minted`; every mint path (`_mint_stat`, `NodeStatBoard._mint_pool`'s redirect) routes through it, so a new mint path must too. `SkillNode`'s defender collision bits are the worked example: key on the local value, not on which addon authored it.
- **`_mint_stat(id)` is the subclass seam**, `_ensure_stat` the gate above it. `EntityStatBoard` refuses to mint (a mint attempt is a typo). `NodeStatBoard` makes `node_health` a `PoolStat` off the `node_combat_health` def. There is no mirror guard on node boards: an entity-only stat there is inert, not wrong.
- **A `sparse = true` entity board (the blockers') drops a modifier for a registered stat it lacks without a warning** (`StatBoard._drops_absent_stat`); an id no `StatDef` declares still warns on every board.

**`SkillNode.node_board` is `@export`ed and `duplicate(true)`d exactly once** (same shape as `Entity.stat_board`; `resource_local_to_scene` doesn't recurse). **`node_board != null` is NOT "initialized" — `_node_board_ready` is**; treating non-null as initialized skips `apply_intrinsics()` forever and silently kills `addon_slots`. The `addon_slots` formula lives in file-backed `stats_system/formulas/stake_scaling.tres` (reads the stake level, the cap N); inlining it forks the curve once per node. Reasoning and measurements: `docs/domain/stat-board-classes.md`.

## Parent stats (ADR 0029, 0030)

**A child stat folds its ancestors' bins, never their base.** `StatDef.parent_ids` declares edges; `StatRegistry` flattens once (`ancestors_of` nearest-first, `children_of`, `is_parent`) and `push_error`s on an unknown id or cycle. A read is `compute(child.base_value, [farthest ancestor … nearest parent, own bins])` at every door via `Stat.all_bins()`, so INCREASEs sum across the chain and a child SET beats a parent SET at equal priority. Invalidation is a link: `StatBoard._link_parents` wires `Stat._parents` / `_children` at the three registration sites (`apply_intrinsics`' typed-field pass, `_register_minted`, `clone_live`), and a parent's `_emit_value_changed` dirties every descendant through the batch branch. **Tests arrange throwaway defs through `StatRegistry.register_def` / `unregister_def`** — nothing outside `test/` calls them. Shipped families: `docs/domain/stats-system.md` § "Parent stats".

## Gotchas

- **`PoolStat.set_current` emits `value_changed`, not just `current_changed`**, so a formula modifier sourcing a pool recomputes on every `current` write. `<stat_id>__<accessor>` tokens route through `Stat.read_accessor(name)` (a per-subclass `accessors()` map), so `health__current` reads `.current`, not the cap; `get_input_ids()` strips to base ids (`StatFormula.base_of`) so the dependency graph keeps seeing `health`. **Don't drop `set_current`'s `value_changed` emit** to save the recompute.
- **Formula accessor tokens are not stats.** `<stat_id>__<accessor>` (double underscore — ids like `min_damage_taken` contain `_`) is a formula-read handle: no `StatDef`, no registry entry, never a valid modifier `stat_id` (rejected at `StatBoard._ensure_stat` and `add_modifier`). `StatFormula.is_accessor_token` is the predicate; accessors: PoolStat `current`, SkillPointStat `wounded`/`staked`/`used`, SurplusPoolStat `surplus`/`available`, GrowablePoolStat `total`. Extend by overriding `accessors()`, not a parallel registry.
- **To read a pool's `current` from a formula use the `__current` token** (`LinearFormula(source_stat_id = &"health__current")`); the bare `&"health"` reads the cap. `get_local_value` understands accessor tokens too: `NodeCombat.get_local_value` branches to `_read_accessor` before its bin merge and *resolves* rather than merges (node board first, then the owner's). Authored tokens are validated at load by `test/unit/spell/test_stat_ranker.gd` — a typo'd base id degrades to `0.0` with no warning.
- **`duplicate(true)` does NOT clone a live board — use `StatBoard.clone_live()`, then `release()`.** `duplicate` copies exports only: every `Stat.bins` is empty and `_extra_stats` (every minted stat, `node_health` included) is missing, with no error. It stays right for a virgin template (`Entity._ready`, `SkillNode._init_node_board`, `EffectContext.grant`). A clone needs three things, each silent when missed: the `_modifiers` list the bins were folded from (`Stat.adopt_modifier_list`; `_resync_bins_if_trivial()` wipes the tally at ≤1 entry), a private copy of every formula-bearing modifier (else it computes but never reacts; static modifiers stay shared, removal by the live handle works via `StatBoard._localized`), and `release()` on the way out (every `Stat` backpoints at its board and `RefCounted` has no cycle collector). `EntityCombat.free_shadow()` releases the entity board and every owned node board; a hand-rolled `clone_live()` does not. Detail: `docs/domain/stat-board-classes.md`.
- **Pool modifiers target the pool id, not a `_max` suffix** (`"health"` is the cap; `"health_max"` doesn't exist).
- **`max` is a GDScript built-in** — never name a property or variable `max` on PoolStat or its subclasses (it shadows `max()`); use `.value` for the cap. Same risk for `min`; `range` is OK because nothing in `StatBoard` calls the global `range()`.
- **StatBoard field name must match the stat's `id`.** `get_stat(id)` calls `Object.get(id)`; renaming either silently breaks lookup.
- **Iterating a typed `Array[StatModifier]` and testing `m is CompositeStatModifier` is a parse error** — copy into an untyped `var mods: Array` first.
- **`Entity.core_modifiers` is the register of modifiers granted to the core, not the class's own list** (class modifiers live in `CoreClass.modifiers`, installed by `core_class.apply`). `Entity._ready` runs `apply_intrinsics()` then `core_class.apply(self)`; don't reorder it (the runtime cycle gate rejects the second arrival).
- **`BalancedCore` must not get a per-level CON entry** — the board intrinsic already owns the level→CON channel and it would double-count.
- **Don't add `StatDef` `display_*` fields** expecting something to pick them up: HudRoot's cards hardcode which stat ids they bind. A new stat is a `.tres` in `stats_system/defs/` plus an entry in `stat_def_roster.tres` (the registry never scans the directory), wired into the right card by id; register its surface (or `hidden` reason) in `docs/domain/stat-surfaces.md`.
- **`SkillNode` modifier doors flatten composites; writes after bind are lost.** `EffectContext.grant_at` sets each duplicate leaf's `value` before granting — never write a modifier after handing it to `grant`/`add_local_modifier`.

## Notification batching

`StatBoard.begin_batch()` … `end_batch()` coalesces `value_changed` into one emission per stat that moved. **Every emit site calls `Stat._emit_value_changed()`**, never `value_changed.emit()` (the raw emit silently opts out). **Always pair it** — an unmatched `begin_batch` swallows every later notification on that board. The flush order by formula dependency depth is load-bearing. Rationale: `docs/domain/stats-system.md` § "Notification batching".

## Wire form (`to_dict` / `read_dict`)

Don't "tidy" these (reasons in the doc § "Wire form"): only accumulated state crosses (never `get_value()`, `bins`, or a pool's cap); the board encodes itself, so **no `Stat.get_modifiers()`**; `read_dict` **reconciles** rather than wipe-and-replay (a wipe strands every `EffectInstance` ledger handle); `PoolStat._read_base` mints and `current` is restored raw (`set_current` would fire `on_pool_filled` / `depleted`); `read_dict` pre-syncs the register via `sync_register_from_wire` before the reconcile.

## BOOL stats

`deflection` is the only `StatDef` with `value_type = BOOL`. A BOOL modifier renders as a bare trait line; **INCREASE / MULTIPLY on a BOOL stat is a content error**. The no-mint invariant holds across the sparse node-local defender tier (`deflection`, `swing_drag`, `blunting`, `spike_regen`): reading one off a node without the granting addon mints nothing (`test_defender_stat_no_mint.gd`).

## Level

`level` is a plain INT `ScalarStat`; `Entity.level` proxies it, and the level-up writes `base_value` (never the effective value). Per-level class bonuses are ordinary modifiers with `formula = level_scaling.tres`; keep that formula file-backed (`duplicate(true)` copies an inline one). Query with `StatModifier.scales_with(&"level")`; level-scaled mods are not lootable. See the doc § "Class identity and level".
