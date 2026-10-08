---
description: Stat system quick-reference — pipeline, stat IDs (grep), intrinsic scaling, gotchas
paths:
  - "stats_system/**"
  - "entity/default_entity_board.tres"
  - "docs/domain/stat-ui-visibility.md"
---

# Stat system reference

> **Breadcrumb:** For which stat appears where in the HUD (or doesn't), see
> `docs/domain/stat-ui-visibility.md`. For *adding* a tuning knob or a new pool
> bin — the authoring decision procedure this file's reference material assumes —
> see `docs/domain/stat-knobs-and-bins.md`.

**Keep current.** Any change to the stat system — new stat, new formula type, modified pipeline, new pool or modifier class, new intrinsic scaling rule — must be followed by updating this rule.

## Modifier pipeline

`(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`

- **SET** short-circuits everything; highest `priority` wins, last-in breaks ties at equal priority; an equal-priority conflict with different values is an authoring error (`push_error`); list order is obtain order, and any rebuild must preserve it (`Stat._resequence`). **Convention:** class-identity SETs (e.g. `pacifist_core.tres` SETting `movement_points`/`deallocation_points` to 0) author `priority = 100` so the anchor sits above any node/keystone/addon SET (those default to 0). Keep class SETs at this tier; leave node content below it.
- **INCREASE** sums additively (PoE-style). Five +20% = ×2.0, NOT (1.2)⁵.
- **The merged pipeline is a value, never re-summed.** `ModifierBins.resolve(sources) -> FoldTerms` (plain `add`/`inc`/`bon`/`mult`/`set_value`, no boards) is the one door to "what the fold is"; `compute` is `resolve().fold(base)`, `Stat.resolve_with(overlays)` is `get_value_with`'s pipeline as a value, `FoldTerms.describe("X")` renders it (`X+3`, `(X+3) × 1.5 + 2`, `= 5`). **Why:** a MULTIPLY bound to a formula only means something on its own source's board, so a readout that concatenated multiplier lists or summed bins itself would silently print the static coefficient. **How to apply:** a readout/clipboard asks for a `FoldTerms` and formats it; the arithmetic lives once in `FoldTerms.arith` (shared with the allocation-free `compute_single`).
- **Op → bin placement has one home: `ModifierBins.add(m, board)`** (SET contests the winner, MULTIPLY joins the list, sum ops add their effective value against `board`; `apply_delta` moves a sum later). `Stat.add_modifier` routes through it, and so does anything building overlay bins (a swing's temp upgrades, `MeleeAttackPlan.overlays_for`, each a `LocalScaleMutator.scaled_copy`). **How to apply:** never a hand-rolled `match m.operation` outside these two.
- **Coercion happens ONCE, at the end, and it is the stat's** (`Stat._coerce`, ADR 0016 / #890): an INT-typed stat **floors its finished total toward zero** (`int(v)` — `10.5 → 10`, `-2.6 → -2`, `0.9 → 0`); FLOAT passes through; BOOL is `v != 0.0`. Nothing else in the pipeline rounds — no bin, no formula (a `RatioFormula` is a line, #891). **Why:** the floor must sit *after* the bins so `% increased` on a ratio target yields `+1 +1 +1` rather than a burst, and a fractional rule (`+1 per 3.75 WIS`) hands out nothing until the step is actually attained. **How to apply:** never `roundi`/`floor` inside a formula or modifier to "make it whole" — the stat does it; a test that wants an exact integer picks a fixture that isn't fractional. A pool's `available()` still `roundi`s its own `current` (that's the current's rounding, not the total's), and display formatting (`StatDef.format_number`, `StatModifier._format_value`) keeps its `roundi` because it formats an already-coerced number.

## Board classes (#332)

`StatBoard` holds **no stat fields** — it is lookup, modifier routing, binding, the cycle gate and the introspection walks. Two **siblings** carry the stats: `EntityStatBoard` (every entity stat as typed `@export` fields, `entity/default_entity_board.tres`) and `NodeStatBoard` (node-**owned** stats baked, borrowed ones sparse, `skill_node/default_node_board.tres`). Siblings, not a chain — a node board is not a specialization of an entity board. The base keeps the name, so every `board: StatBoard` parameter stays polymorphic and unchanged.

Five things that fail silently if you forget them:

- **Bake what the node owns; stay sparse for what it borrows.** `get_local_value` merges as `ModifierBins.compute(entity_stat.base_value, [entity.bins, node.bins])`, so for any id the entity *also* carries, the node stat's own `base_value` is **discarded** — authoring `armor = 5` on a node board does nothing, no error. Only `stake_level`, `addon_slots`, `arrows_per_reload` and `max_shots_per_leaf` are node-owned and baked (the latter two solely so their MULTIPLY-by-`stake_level__current` intrinsics have a non-minting `get_stat` target to bind to, #955/#956 — `base_value` is still inert, only `bins` ever gets read); `node_health` is borrowed (the entity carries the baseline).
- **`get_dynamic_stat_ids()` reads `_extra_stats` only** — promoting a stat to a typed field drops it from that answer. Display code wants **`get_stat_ids()`** (fields + mints); reserve the dynamic call for genuine "what got minted" assertions.
- **A sparse stat does not exist until it is minted, so `get_stat(id)` returns `null` at ready time — subscribe via `StatBoard.stat_created(id, stat)` (#810), never by polling.** That signal is the only hook for "a sparse stat now exists to connect to"; it fires once per id, since `_extra_stats` entries are never erased. It is emitted from the single `_extra_stats` writer, `StatBoard._register_minted` — every mint path (`_mint_stat`, and `NodeStatBoard._mint_pool`'s `node_health`/`spikes` redirect) routes through it rather than assigning `_extra_stats[...]` directly, so a future third mint path cannot silently skip the emit (#812, fixing a real gap where `_mint_pool` used to bypass it). `SkillNode`'s defender collision bits are the worked example: connect `stat_created`, subscribe the stat's own `value_changed`, and key on the LOCAL VALUE rather than on which addon authored it — a bare granted `StatModifier` must flip it exactly like an addon does.
- **`_mint_stat(id)` is the subclass seam**, `_ensure_stat` is the gate above it (accessor tokens, already-exists). `EntityStatBoard` refuses to mint — a mint attempt there is a typo. `NodeStatBoard` makes `node_health` a `PoolStat` off the `node_combat_health` def. There is deliberately **no mirror guard** on node boards: an entity-only stat there is inert, not wrong.
- **A `sparse = true` entity board (the blockers') drops a modifier for a registered stat it lacks without a warning** — owning a node lands every entity-scoped modifier on it. An id no `StatDef` declares still warns on every board. The seam is `StatBoard._drops_absent_stat`.
- **`SkillNode.node_board` is `@export`ed and scene-composable, and is `duplicate(true)`d exactly once** — same shape as `Entity.stat_board`, so a level/cluster/node may author its own and a saved level serializes real per-node state. Deep clone because `resource_local_to_scene` does not recurse into sub-resources (every node would share one set of Stats). **`node_board != null` is NOT "initialized"** — `_node_board_ready` is; treating non-null as initialized makes a scene-authored board skip `apply_intrinsics()` forever and silently kills `addon_slots`. Assigning `node_board` resets that flag, so `= null` still yields a board-less node. The `addon_slots` formula lives in `stats_system/formulas/allocation_scaling.tres` and must stay **file-backed** — `duplicate(true)` copies an inline sub-resource, so inlining it forks the curve once per node with no error.

Full reasoning, the sub-board-array alternative that was rejected, and the +153 ms/2500-node measurement with its breakdown: **`docs/domain/stat-board-classes.md`**.

## Parent stats (ADR 0029, ADR 0030)

**A child stat folds its ancestors' BINS, never their base.** `StatDef.parent_ids` declares the edges; `StatRegistry` flattens them once (`ancestors_of` nearest-first + deduped, `children_of` direct, `is_parent`), `push_error`s and drops an unknown id or a cycle-closing edge. A read is `compute(child.base_value, [farthest ancestor … nearest parent, own bins])` at every door (`get_value`, `get_value_with`, `resolve_with`, `PoolStat`'s `base_provider` read) via `Stat.all_bins()` — so INCREASEs sum across the chain and a child SET beats a parent SET at equal priority. **Invalidation is a link, not a signal:** `StatBoard._link_parents` wires `Stat._parents` (present ancestors) / `_children` (present descendants) at the three registration sites (`apply_intrinsics`' typed-field pass, `_register_minted`, `clone_live`), both ways, and a parent's `_emit_value_changed` dirties + notifies every descendant through the batch branch; parent edges join `collect_formula_edges` so a flush emits parents first. **Tests arrange throwaway defs through `StatRegistry.register_def` / `unregister_def`** — nothing outside `test/` may call them.

**Shipped families** (#1184): `damage` → `blade/spell/ranged_damage`; `attributes` → the six attributes; `status_resistance` → every `<aspect>_resistance` (#1456); `dot_stacks_per_hit` → the four `<family>_stacks_per_hit`; `aspects` → the eight `<concept>_aspect` (#1248). Each parent is an ordinary typed `ScalarStat` on `EntityStatBoard` (default 0, its own value never read), so a sparse board drops a family modifier like any absent stat. A node-local grant on a parent reaches a node with no child stat of its own (`bins_for`) — the Ninja's Phantom Strike is one `+5 damage`. A consumer that lists stats by id must list the child only, never child + parent.

## Local stats (per-node overrides)

Long form moved: `docs/domain/stats-system.md` § "Local stats (per-node overrides)". Read it before editing this area.

## Pool stats

Long form moved: `docs/domain/stats-system.md` § "Pool stats". Read it before editing this area.

## Turn-start upkeep

Long form moved: `docs/domain/stats-system.md` § "Turn-start upkeep". Read it before editing this area.

## Dependency-cycle rejection (#322)

Long form moved: `docs/domain/stats-system.md` § "Dependency-cycle rejection (#322)". Read it before editing this area.

## Modifier packs (#183, D-27/#279)

`CompositeStatModifier extends StatModifier` is **a modifier pack, optionally
atomic for loot** — not just a loot bundle. It bundles several child modifiers
into **one atom** for the storage/authoring layer, while flattening into its
children wherever a modifier is actually **applied** or fully **listed**. Two
uses, both by reference (author one `.tres`, drop it into any `CoreClass.modifiers`
array, edit it and every class composing it changes):

- **Plain authoring reuse** (`loots_as_unit = false`) — a shared batch with
  nothing all-or-nothing about it, e.g. `stats_system/packs/attribute_baseline.tres`
  (+10 STR/DEX/INT), referenced from `balanced_core`, `basic_enemy_core`, and
  `ninja_core`. `LootSystem._expand_for_loot` expands these into separate
  candidates before the lootability filter runs, so a `false` pack with a mixed
  static/level-scaling child set filters per-leaf instead of excluding the whole
  pack.
- **A loot bundle** (`loots_as_unit = true`, the default) — a class-identity
  buff/debuff pair balanced only as a unit — authored as one `CoreClass.modifiers`
  entry, it loots all-or-nothing so a collector can't cherry-pick the buff (see
  `ninja_core.tres`'s `mod_budget_pack` = +2 DP / −1 SP).

**A `CoreClass` `.tres` is a leaf (D-27).** It never references another
`CoreClass` — shared batches live inside its typed arrays (`modifiers` via a
pack, `effects` via a shared `Effect` `.tres`, e.g. an `AuraEffect` subclass) instead. Packs live
outside `entity/core/` (`stats_system/packs/`) so `CoreClass.load_all()` never
picks one up as a phantom selectable class. Two class-level mechanisms
(`inherits: CoreClass`, then `composes: Array[CoreClass]`) were built and
reverted before this landed — see D-27 in `docs/adr/legacy-mvp-decisions.md` for why.

**The whole feature is one virtual: `StatModifier.flatten() -> Array[StatModifier]`.**
A leaf returns `[self]`; the composite returns its children (recursively). Two
worlds:

- **Keep whole (storage/authoring/loot):** `CoreClass.modifiers`,
  `core_location.modifiers`, loot `candidates` — a composite is ONE entry / ONE
  pick-N-from-M candidate.
- **Flatten (application/full-listing):** two apply seams flatten and route
  each leaf — `StatBoard.add_modifier`/`remove_modifier` (entity board:
  allocation, addons' `entity_modifiers`, effects, intrinsics, loot grant) and
  `SkillNode.add_local_modifier`/`remove_local_modifier` (node board: addons'
  `local_modifiers`, node-scoped effect grants). So **every** application path
  gets bundle support for free. Display / per-mod-floater sites that list every
  leaf flatten too: `GrantedModifiersRoot._rebuild_rows`, `LootPicker._make_card`
  (one card per candidate, body lists the leaves), `SkillDustAddon._grant_mods`
  and `AllocationVfx` (the #70 floaters — **one per leaf**, honest about each
  stat gained). `StatModifier.flatten_all(mods)` is the list-level helper for
  the per-entry iterators.

**INERT container:** the composite's own `stat_id`/`operation`/`value`/`formula`/
`priority` are vestigial (hidden via `_validate_property`); only leaves bind and
apply. Because add_modifier flattens, a child's `emit_changed()` reaches its Stat
through the normal wiring — the container never proxies signals. `duplicate(true)`
deep-copies the `children` array (verified — Godot recurses into an exported
Array of Resources), so no `duplicate()` override is needed and the per-element
dup discipline for formula-bound mods holds for a bundle too.

**Gotcha:** iterating a typed `Array[StatModifier]` and testing `m is
CompositeStatModifier` is a parse error (the element type resolves by script
*path*, the class by *class_name*, and the analyzer won't narrow between them).
Copy into an untyped `var mods: Array` first. See `test_composite_stat_modifier.gd`.

## Effect-granted modifiers (#4)

Long form moved: `docs/domain/stats-system.md` § "Effect-granted modifiers (#4)". Read it before editing this area.

## Class identity modifiers (CoreClass)

Per-entity class bonuses live on `Entity.core_class: CoreClass` (`entity/core/`), NOT on the stat board's intrinsic list or as an Entity-level modifier array (the old `Entity.core_modifiers` field was removed). `Entity._ready` calls `core_class.apply(self)` once, which installs every entry in `CoreClass.modifiers` directly — **no per-entry duplication** (#377): the same `.tres` and the same modifier instances are safe across every entity of that class, since binding lives on each entity's own board (`StatBoard.bind_modifier`), not on the modifier. `BalancedCore` is the +10 STR/DEX/INT baseline (plus +1 each per level — see "Per-level class bonuses" below) against which other classes are tuned; create new classes by extending `CoreClass` and authoring a `.tres`. Procgen sandboxes wire the class via `GameRoot.spawn_entity(..., core_class)`; hand-authored scenes set it on the Entity node directly.

## Stat IDs

Mana and mana regen were retired 2026-10-03 (ADR 0045); restore from tag `retired/mana`, never re-add ad hoc.

Run to list all current stat IDs:
```
grep -h "^id = " stats_system/defs/*.tres | sort
```

- **`core_kill_xp` (#774)** — a flat, board-authored scalar `loot_system.gd`
  adds once on top of the territory term when the victim's own core dies. Not
  a multiplier, not derived: 60 on `default_entity_board.tres` (players/NPCs),
  20 / 40 / 60 on the small / medium / large blocker boards — tune per board
  like any other stat, reachable by a modifier same as the rest.

## `StatDef.ValueType.BOOL` (#805) — a stat that is presence, not a magnitude

`deflection` (#781/#805) is the first, and today the only, `StatDef` authored
`value_type = BOOL`. Pick BOOL over INT for a stat whose only meaningful
question is "granted or not" — where a magnitude would be actively misleading
(a second source doesn't make it "twice as present"). `armor`, `blunting`,
`spike_regen`, `swing_drag` stay INT/FLOAT deliberately; they're read as real
magnitudes (summed, accumulated, thresholded). `deflection` is read as
`bool(sn.get_local_value(&"deflection"))` in exactly one place,
`MeleeAttackPlan.build_obstacle_field` — never `float(...) <= 0.0`.

Two branches this traffic exercises for the first time:

- **`Stat._coerce`**: `v != 0.0` — hands back a real GDScript `bool`, not a
  float that merely compares true-ish. `get_local_value` on a bunkered node
  returns that bool directly.
- **`ModifierPoolEntry`'s BOOL branch** clamps a rolled ADD_BASE/ADD_BONUS to
  `1.0`/`0.0`. Stays untravelled for `deflection` — it's addon-authored, in no
  procgen pool. Don't build a pool entry just to reach it.

**Display is a separate concern from the read, and has two doors, both
type-aware (#622):**

- `StatDef.format_number(BOOL, v)` → `"True"` / `"False"` — the direct-value
  path (`StatValueRow` binding a stat's own computed value).
- `StatModifier._format_value` — a BOOL modifier renders as a **bare trait
  line**: the stat's display name alone, no sign, no number, regardless of
  op (owner call, 2026-09-09: "presence, not magnitude" all the way down to
  the tooltip — no per-addon opt-out, every future BOOL stat inherits this for
  free). `+5 bonus Armor` next to a BOOL modifier reads `Deflection`, not
  `+1 bonus Deflection`. **INCREASE / MULTIPLY on a BOOL stat is a content
  error** (there's no magnitude to scale) — `push_warning`s rather than
  silently falling through, same "reject and keep running" shape as the rest
  of the pipeline; still renders the bare trait line rather than erroring.
  `contribution_text` (the stat-name-omitted "+10"/"×1.5" form used by the
  editor visualizer and the #70 per-leaf allocation floaters) is untouched —
  out of scope, not itself type-aware today.

**The no-mint invariant holds across this whole sparse node-local defender
tier** (`deflection`, `swing_drag`, `blunting`, `spike_regen`) — reading any of
them off a node that never had the granting addon returns the def default and
mints nothing on either board. Pinned by `test_defender_stat_no_mint.gd`
(generalizes `test_stake_level_poolstat.gd`'s single-stat pin).

## `level` is a plain ScalarStat, written imperatively (#200)

`level` lives on the board as an ordinary `ScalarStat` (id `level`, INT, default 1) — **not** a bespoke derived/read-only class and **not** a `fill_count` on `PoolStat`. It exists so level-scaling formula modifiers (`+level × 1 STR`, #194) can `board.get_stat(&"level")` and auto-recalc: `Entity._on_xp_replenished` does `stat_board.level.base_value += 1`, and `base_value`'s setter emits `value_changed`, which walks the same reactive path as any formula source (PER→vision, etc.). No new mechanism.

Consequences to respect:
- **`Entity.level` is a proxy** onto `stat_board.level.value` (getter) / `.base_value` (setter), with a `1` fallback for sparse/test boards that carry no `level` stat. There's no separate `int` counter — the stat is the single store. Don't reintroduce one.
- Level stays **moddable** like every other stat (a `+2 level` modifier is legal and lifts effective level). That's deliberate — don't special-case it read-only.
- The level-up path writes `base_value` (not effective value) so it never double-counts any level modifiers.

## Per-level class bonuses ride the ordinary `modifiers` array (#194)

There is **no `level_up_modifiers` field and no per-level-up mutation.** A "+1 STR per level" class bonus is one ordinary `StatModifier` in `CoreClass.modifiers` with `value = 1.0` (the coefficient) and `formula = level_scaling.tres`. Level-up writes `level.base_value`, that emits `value_changed`, the bound modifier recomputes — the reactive chain is the one every other formula uses. Adding a fresh `+1 STR` modifier on each level-up is the anti-pattern: N modifier instances, N subscriptions, and cleanup on death.

**The curve is shared and lives in one file:** `stats_system/formulas/level_scaling.tres` is `ExpressionFormula("level - 1")`. Every class references that same file, so retuning the level curve is a one-file edit. It's `level - 1`, not `level`, so a level-1 entity sits exactly on its authored baseline (Balanced reads +10, not +11) and each level-up adds the coefficient.

**Keep the formula in its own `.tres` — never inline it into a class.** `Resource.duplicate(true)` **preserves the identity of a file-backed sub-resource and copies an inline one** (verified empirically under Godot 4.4, both directions). `CoreClass.apply()` itself no longer duplicates anything (#377 — below), so inlining the formula wouldn't fork it *there*. But two other paths still duplicate the whole board/modifier and would still fork an inline formula silently: the `Entity.stat_board` setter's `duplicate(true)` (deep-copies `intrinsic_modifiers`; it is what keeps one board template shared by every entity) and `EffectContext.grant()` (still `.duplicate(true)`s once per grant). File-backed keeps the curve shared through both; inline would quietly break the shared-tuning property in either. It also explains why `composite_stat_modifier.gd` can claim `duplicate(true)` deep-copies its `children`: those are inline.

Sharing one formula instance across entities was always safe because `StatFormula` is stateless — it reads its inputs from whatever board is passed to `compute(board)`, with nothing cached on the formula itself.

**A `StatModifier` instance can live on N boards at once (#377).** Both it and
`StatFormula` are stateless — binding lives on `StatBoard` (`bind_modifier` /
`unbind_modifier`, recomputed from `formula.get_input_ids()` each call).
`CoreClass.apply()` and `StatBoard.apply_intrinsics()` dropped their defensive
`.duplicate(true)` as a direct consequence. Sharing a granted modifier so it
recalculates on every holding entity's board already works.

**Query level bonuses with `StatModifier.scales_with(&"level")`**, not a marker field or resource identity. The formula's declared `get_input_ids()` already answer "does this scale with level?", the answer survives duplication, and it stays true for a class that authors its own `ExpressionFormula("(level - 1) * dexterity")` instead of the shared curve. It asks every leaf via `flatten()`, so a composite reports true when any child scales. Two call sites use it with opposite signs — the #199 HUD listing (include) and `LootSystem._is_lootable` (exclude). Route any third through the same predicate.

**Level-scaled mods are not lootable.** They vanish with the entity like the rest of the core set, but the loot draw excludes them: a looted copy keeps the shared formula and would rebind to the *looter's* level, granting a scaling relic nobody designed. Lootable relics that scale with the holder's level are a real feature — if wanted, design it deliberately, don't let it fall out of the draw.

## Intrinsic scaling (entity/default_entity_board.tres)

These are `StatModifier` sub-resources with a `formula`, wired as `intrinsic_modifiers` on the default board — all entities get them. Keep them inline in the board .tres (not separate files). Effective contribution = `modifier.value × formula.compute(board)`; with `value = 1` the formula reads through. A `RatioFormula` row below is a line — `+1 per 20 STR` contributes `0.05 × STR` continuously and the INT target floors once at the end (#891), so a merged loot copy (`value 1.25`) moves the step to 16 STR rather than doing nothing until four copies stack. **Update this table when adding or changing one.**

| Input stat | Target stat | Op | value | formula |
|---|---|---|---|---|
| `perception` | `vision_range` | INCREASE | 2 | LinearFormula(perception) — at PER=3 → +6% |
| `perception` | `sensor_range` | ADD_BASE | 1 | ThresholdFormula(perception, [3, 8, 21, 55, 149, 404, 1097, 2981, 8104, 22027]) — exactly `floor(ln PER)`, `ceil(e^n)` per rung (#547, moved from WIS to PER — owner call 2026-09-11: PER has two jobs, vision + sensor range; WIS has one, XP/turn) |
| `wisdom` | `xp_per_turn` | ADD_BASE | 1 | RatioFormula(wisdom, **5**) — #776 divisor pass, starting value |
| `dexterity` | `range` | INCREASE | 1 | LinearFormula(dexterity) — at DEX=30 → +30% |
| `dexterity` | `ranged_damage` | ADD_BASE | 1 | RatioFormula(dexterity, **20**) — #776 divisor pass, starting value |
| `intelligence` | `cast_range_distance` | INCREASE | 1 | RatioFormula(intelligence, **50**) — a line, +1% increased euclidean reach per 50 INT, over the spell's authored `max_distance` (folded as an overlay, stat base 0 by contract — #912) |
| `intelligence` | `cast_range_hops` | ADD_BASE | 1 | ThresholdFormula(intelligence, [50, 150, 500, 1000, 5000]) — flat +1..+5 hops over the spell's authored `max_hops` (overlay, base 0 by contract — #912), feeds `HopRangeFinder` only, never `PropagationConfig.max_hops`; breakpoints retune post-LAN |
| `intelligence` | `spell_damage` | ADD_BASE | 1 | SqrtFormula(intelligence, divisor=1) — pure sqrt transfer, no knee (#776 amendment, superseding #760's KneeSqrtFormula); `divisor` a drone starting value, not the owner's |
| `intelligence` | `infusion_slots` | ADD_BASE | 1 | ThresholdFormula(intelligence, [100, 1000, 10000]) — slots a cast can fill, one concept per slot (owner ladder, #1462) |
| `intelligence` | `infusion_points` | ADD_BASE | 1 | SqrtFormula(intelligence, divisor=1) — points per slot (owner, #1462) |
| `strength` | `blade_size` | ADD_BASE | 1 | RatioFormula(strength, **40**) — #776 divisor pass, starting value |
| `strength` | `blade_damage` | ADD_BASE | 1 | RatioFormula(strength, **20**) — #776 divisor pass, starting value |
| `constitution` + `node_health_scaling` | `node_health` | ADD_BASE | 1 | `node_health_scaling * constitution` (D-26 precedent, #298) — the rate is the **stat**, not the coefficient (see below) |
| `constitution` + `core_health_scaling` | `health` | ADD_BASE | 1 | `core_health_scaling * constitution` (D-21/D-26, #276) — the rate is the **stat**, not the coefficient (see below) |
| `level` | `constitution` | ADD_BASE | 1 | `level_scaling.tres` (`level - 1`) — TBD (#268), +1 CON per level |
| `max_shots_per_leaf` | `volleys_per_turn` | ADD_BONUS | 1 | LinearFormula(max_shots_per_leaf) — base 0, reads 5 by default (#956) |

## Intrinsic scaling (node board)

Long form moved: `docs/domain/stats-system.md` § "Intrinsic scaling (node board)". Read it before editing this area.

## Damage mitigation

`Mitigation.apply(raw, defender_board)` (`attack/formulas/mitigation.gd`) runs inside `SkillNode.take_damage` before HP soak. Formula:

```
final = max(min_damage_taken, raw.amount - armor)
```

- `TRUE`-typed damage bypasses everything and lands raw.
- `raw.amount <= 0` returns 0 — the floor only triggers on a real hit.
- `armor` scalar (default 0) and `min_damage_taken` scalar (default 3) are both standard board stats — modifiers / intrinsics apply normally. Defensive cores (e.g. Bulwark) can drive `min_damage_taken` below 0, allowing damage to *heal* nodes if the underflow is large enough.
- Rare procgen modifier `-1 min_damage_taken` is a high-tier exotic roll.

## DoT stacks / resistance (#963, #1189, hub #952)

Each status folds through **one** attacker-side stacks stat and one defender-side resistance. Stacks (FLOAT, entity-scope, default 0): `poison_stacks_per_hit`, `corruption_stacks_per_hit`, `curse_stacks_per_hit`, `wither_stacks_per_hit`, whose **parent** (`parent_ids`) is the umbrella `dot_stacks_per_hit`, plus the parentless `blindness_stacks_per_hit` (blindness is not a DoT). Bleeding and Hex follow the same shape: `bleeding_stacks_per_hit` / `hex_stacks_per_hit` (FLOAT, entity-scope, parentless), `bleeding_resistance` (parent `status_resistance`), and the identity-aspect stats `bleeding_aspect` / `hex_aspect` (parent `aspects`). Potency is gone (ADR 0029): the multipliers are the stacks stat's own INCREASE / MORE bins. A `StatusDef` names its stat in `stacks_stat_id` (armor-break: blank) and `StatusDef.stacks_per_hit(board, authored)` is the one fold — the authored per-hit power is a `base_add` overlay, one `get_value_with` read, so flats add to it, multipliers scale it, the umbrella folds in once; **never floored** (1 × +49% lands 1.49). A null board, blank id or unknown stat answers the authored power. `StatusInstance.land_on` lands that **once** (`power_resolved`) — resistance never scales it; the one land-time read is the 100% gate (`blocks_status` → power 0) — and `AttackRecord.rebuild` marks the hit resolved so a peer replays the landed number flat; the on-hit readout calls the same function.

Resistances (FLOAT, default 0.0, a fraction): `poison_resistance`, `corruption_resistance`, `curse_resistance`, `blindness_resistance` (Wither has none, #1456), read on the **host** via `get_local_value` like armor (node slice, or the entity on fall-through). They are a **live filter at effect time** (ADR 0031): `StatusHost.effective_power` hands every apply/tick `row − ⌈row × res − ½⌉` (half-down, clamped to `[0, row]`) while the row decays raw; `>= 1.0` blocks landing and a standing row deals 0 but decays. `DotTick.tick_damage` floors each projected tick through `HitPoints.land`, so `projected_status_damage` equals what lands. Procgen (#974, #1058, #1059, #1095): each family lives in one attribute pack — poison DEX, corruption STR, curse CON, wither INT, blindness PER; the resistance (wither excepted) rolls on **blessed** nodes only, ADD_BASE (unit 0.05), T2–T4; the stacks stat's INCREASE row (unit 7 → +7/+21/+49%) on **blighted** nodes only; `dot_stacks_per_hit` ADD_BASE on blighted WIS. See `docs/domain/effect-system.md` § "Status effects — the DoT model".

**`healing_received` (#966, Wither)** — FLOAT, default 1.0, read node-locally **once** at the top of `NodeCombat.heal_damage` (the one node door every heal takes: turn regen, the core aura, healing spells) and entity-locally **once** at the top of `EntityCombat.heal` (the one entity door: the `core_healing` HOST_ADD upkeep; a negative product drains the pool as TRUE damage through `take_pool_damage`, and the pool has no gate to close). Both doors take `raw := true` as the only bypass; `test_heal_door_drift.gd` guards the rest of the tree (#997). Product `<= 0` heals nothing and cures nothing; product `< 0` lands as TRUE damage flagged `DamageInstance.from_withered_heal`, the single damage path that does **not** set `_damaged_since_upkeep` — the regen ramp keeps climbing and the node heals itself to death. `WitherStatus` plants an unclamped UNSCALED MULTIPLY of `1 − 0.1·stacks` on it.

**Both stats are read node-locally.** `Mitigation.apply(raw, defender)` takes the
`SkillNode` and reads `defender.get_local_value(&"armor")` /
`get_local_value(&"min_damage_taken")`, which merges the node's `node_board` bins
with the owner's board through one `ModifierBins.compute`. So a node-scoped
defensive modifier — `bunker_addon.tscn`'s `armor ADD_BONUS +5`, or a core-class
aura — actually reaches the damage formula.

> This was broken until **be477f5**: `take_damage` passed `owned_by.stat_board`,
> the *entity* board, so every node-local `armor` was silently discarded while
> `combat_readout_card.gd` happily displayed it. Tooltip said +5, combat
> disagreed, no error either way. Recorded because the failure mode — a
> node-local stat that displays correctly and computes wrong — is easy to
> reintroduce in any new formula that takes a board instead of a node.

Note the floor is a floor, not a cap: negative armor pushes damage *above* raw,
but only once `raw - armor > min_damage_taken` (default 3). At `raw=1, armor=-1`
you take 3, not 2.

## Forced-dealloc damage

When a node's combat HP hits 0, `BattleSystem._on_node_depleted` runs the cascade (impact + islanded set). Each cascaded node costs the defender two things, neither going through `Mitigation`:

- `skill_points.wound(1)` — moves 1 SP from `used` → `wounded`. Currency exchange; SP isn't refunded, it's reserved until `wound_heal_per_turn` ticks it back. Knob: hardcoded 1 (one node lost = one wound, tight coupling on purpose).
- `health.deplete(dealloc_damage.value)` — chip damage off the entity HP pool. Default 1. **Tuning lever** — a fragile-core class can raise it (e.g. Glass Cannon = 3) to make every cascaded node hurt more. Skips `Mitigation.apply` deliberately — wounds and dealloc damage are explicitly "bypass armor" by design (read the user-facing framing: it's a currency exchange, not an attack landing).

Both are emitted per cascaded node in the same loop, so a 5-node cascade with `dealloc_damage = 2` deals 5 wounds + 10 HP, ignoring armor.

## Notification batching (`begin_batch` / `end_batch`)

`StatBoard.begin_batch()` … `end_batch()` coalesces `value_changed` into **one
emission per stat that moved**. `SkillNode.apply_entity_modifiers_to` /
`remove_entity_modifiers_from` wrap their loops in one — an allocation is one
logical event, and without it a node granting both `constitution` and
`node_health` cascaded twice, each cascade re-syncing every owned node's HP pool
(75–83% of an allocation's cost at 200 owned; see `test/perf/bench_allocation_cost.gd`).

- **Every emit site must call `Stat._emit_value_changed()`, not
  `value_changed.emit()`** — that helper is what defers to the board. A new site
  using the raw emit silently opts out of batching.
- **Defers notification, never value.** `get_value()` recomputes from the bins,
  so a mid-batch read is already correct. `PoolStat._apply_max_change` runs on
  the add/remove path, not off `value_changed`, so ratcheting is unaffected.
- **The flush is ordered by formula dependency depth, and that ordering is
  load-bearing**: emitting a source re-dirties its dependents, so a dependent
  emitted too early gets a second full cascade. `end_batch` keeps the depth up
  during the flush and erases each stat before emitting it. Nested pairs flush
  once, at the outermost end.
- **Always pair it** — an unmatched `begin_batch` swallows every later
  notification on that board.
- Contract tests: `test/unit/test_stat_board_batch.gd`. Its ordering test dirties
  the dependent FIRST on purpose; insertion order is otherwise accidentally
  correct and the test passes vacuously.

## Gotchas

- **`PoolStat.set_current` emits `value_changed`, not just `current_changed`.** Consequence (now resolved): a formula modifier sourcing a pool **recomputes on every `current` write** — every hit, every tick — so the read had better be the right one. Pre-#333 `LinearFormula`/`RatioFormula`/`ExpressionFormula` bottoms out in `board.get_stat(id).get_value()`, which is the **cap**, so the recomputation was wasted on a wrong read. #333 split the read: `<stat_id>__<accessor>` tokens route through `Stat.read_accessor(name)`, which dispatches to a per-subclass `accessors()` map — so `health__current` reads `.current`, not the cap. `get_input_ids()` strips to base ids (`StatFormula.base_of`), so the dependency graph (and `StatBoard.cycle_from`) keep seeing `health`, not a phantom `health__current` vertex. The recompute cost is the price of correct subscription — **don't** optimize it by dropping `set_current`'s `value_changed` emit; the first formula to source `initiative` (ticks constantly) or `health` (every hit) folds it into a real perf budget, and that's a separate issue.
- **Formula accessor tokens are NOT stats.** `<stat_id>__<accessor>` (the `__`-double-underscore join — single `_` is ambiguous: ids like `min_damage_taken` contain it) is a formula-read handle, not a stat id. No `StatDef`, no `StatRegistry` entry, no write path through the modifier pipeline, never valid as a modifier `stat_id` (rejected at `StatBoard._ensure_stat` and `StatBoard.add_modifier` with a specific push_warning). `StatFormula.is_accessor_token` is the predicate. `Stat.accessors()` is the per-subclass discovery key (PoolStat→`current`, SkillPointStat→`wounded`/`staked`/`used`, SurplusPoolStat→`surplus`/`available`, GrowablePoolStat→`total`) — extend it the same way `CoreClass.load_all()` replaced a hand-maintained loader list: by overriding one method, not by editing a parallel registry.
- **Formula-driven modifiers can be shared across entities/boards freely (#377).** No binding state on the modifier — `StatBoard.bind_modifier`/`unbind_modifier` own the reactive wiring per-board, recomputed from the modifier's own `formula.get_input_ids()` each call. `.duplicate(true)` before `add_modifier()` is no longer required for this reason; keep it only when you want a genuinely independent *value* per grant (loot draws, addon sub-resources without `resource_local_to_scene`) — that's a content-identity concern, not a binding one.
- **`duplicate(true)` does NOT clone a *live* board — use `StatBoard.clone_live()`, then `release()` when done (#498/#506/#514).** `duplicate` copies exports only, so every `Stat.bins` comes back empty and `_extra_stats` (every minted stat, `node_health` among them) is missing outright — no error, the clone just reads as an unmodified board. It stays right for a **virgin template** you then build up (`Entity._ready`, `SkillNode._init_node_board`, `EffectContext.grant`), which is why nothing noticed until a combat shadow needed the other kind. Three things a clone needs that `duplicate` cannot give it, each silent when missed:
  - **The `_modifiers` list the bins were folded from.** `_resync_bins_if_trivial()` wipes the tally the moment that list holds ≤1 entry (40 STR → 20 after a +10). `Stat.adopt_modifier_list` is the carry — never populate bins without it.
  - **A private copy of every formula-bearing modifier**, or the clone computes but never *reacts*. Binding the shared instances instead is the obvious fix and is wrong twice: it fires recomputes on the LIVE board, and it strands the clone's stats behind a modifier the live board owns. Static modifiers stay shared; removal by the caller's live handle still works via `StatBoard._localized`.
  - **`release()` on the way out**, or the clone is never collected at all: every `Stat` backpoints at its board and `RefCounted` has no cycle collector (122 objects per clone, 0 after). `EntityCombat.free_shadow()` does it for the entity board and every owned node board, so shadow callers get it free; a hand-rolled `clone_live()` does not. It refuses a live board.

  Costs, the four ways to get the copies subtly wrong, and the measurements: `docs/domain/stat-board-classes.md`.
- **Pool modifiers target the pool id, not a `_max` suffix.** `"health"` targets the health cap. `"health_max"` doesn't exist.
- **`get_local_value` understands accessor tokens too, since #702** — `node.get_local_value(&"node_health__current")` reads that node's damage, not its cap. `NodeCombat.get_local_value` branches to `_read_accessor` before its bin merge and **resolves rather than merges**, node board first then the owner's: the merge is meaningful for a modifier-computed cap and meaningless for `.current`/`wounded`/`surplus`, which live on exactly one `Stat` instance. So `skill_points__wounded` works there for free (misses the node board, finds the owner's `SkillPointStat`). The grammar itself is not reimplemented — `get_local_value` is a fifth caller of `StatFormula`'s statics + `Stat.read_accessor`, alongside the four formula classes. Authored tokens are validated at load by `test/unit/spell/test_stat_ranker.gd`, because a typo'd *base* id degrades to `0.0` with no warning and no read-time policy can catch it.
- **To read a pool's *current* (or a subclass bin) from a formula, use the `__<accessor>` token.** `LinearFormula(source_stat_id = &"health__current")`, `RatioFormula(source_stat_id = ...)`, or an `ExpressionFormula` whose `inputs` and `formula` use `health__current`. The bare token `&"health"` still reads the cap — every shipped formula uses this, and every named accessor goes through `__`. Same `get_input_ids()` returns `health` for both, so a "scale with how full this pool is" modifier caries the same dependency edge as a cap reader.
- **`max` is a GDScript built-in.** Never name a property or variable `max` on PoolStat or its subclasses — it shadows `max()` in all subclass methods. Use `.value` for the cap. (Same risk for `range`, `min`, etc. — the `range` stat property is OK because nothing in `StatBoard`'s methods calls the global `range()`.)
- **StatBoard field name must match the stat's `id` string.** `get_stat(id)` calls `Object.get(id)` — renaming either without the other silently breaks lookup.

## Wire form (`to_dict` / `read_dict`) — #560

`StatBoard.to_dict()` → `{stat_id: Stat.to_dict()}`; `Stat.to_dict()` →
`{"base": base_value, "mods": [StatModifier.to_dict(), …]}`, extended by
`super()` down the pool chain (`PoolStat` adds `current`, `SkillPointStat` adds
`wounded`/`staked`, `SurplusPoolStat` adds `surplus`). Consumed by
`network/entity_snapshot.gd` for the join handshake. Four things that are
deliberate and will bite if "tidied":

- **Only ACCUMULATED state crosses.** Never `get_value()`, never a `bins` field,
  never a pool's cap — the receiver recomputes all of it from base + the
  modifier list. `used` on `SkillPointStat` is derived and therefore absent too.
- **The board encodes ITSELF — do NOT add `Stat.get_modifiers()`.** `_modifiers`
  never leaves the `Stat` (see `collect_formula_edges`'s own note: an escaped
  array lets a caller append an unbound modifier that sits in the list
  contributing nothing to `bins` — silently wrong, no error). An encoder that is
  a visitor from outside would need that hole. `test_entity_snapshot.gd` asserts
  neither class has such a method.
- **`read_dict` RECONCILES, it does not wipe and replay.** An existing modifier
  whose wire form equals an incoming one is kept in place; only genuinely-new is
  minted, only genuinely-absent removed. That is what keeps an
  `EffectInstance`'s grant ledger (which revokes by object IDENTITY) valid
  across a decode — a wipe leaves every effect holding a handle to something no
  longer on the board, so its buff sticks forever. Matching walks `_modifiers`
  **newest-first** for the same reason: during `EntitySnapshot`'s second pass a
  node-sourced effect's fresh grant sits next to pass 1's decoded copy of it,
  and the later one is the ledgered handle.
- **`PoolStat._read_base` mints, and `current` is restored RAW.**
  `_set_base_minted` is the fourth mint site (all four inside `stats_system/`) —
  transporting a cap is not a cap CHANGE, so the def's rise/fall policy must not
  move the `current` the payload restores one line later. `current` skips
  `set_current` for the mirror-image reason: its crossings would fire
  `on_pool_filled` (a full `xp` pool levels the entity up on arrival) and
  `depleted` (a `health` pool at 0 kills it). A snapshot transports a state that
  already happened; it must not re-run its consequences. `current_changed` /
  `value_changed` are emitted by hand instead, so UI still updates.
- **`StatBoard.read_dict` pre-syncs the REGISTER before the reconcile above
  runs (#775 late-join amendment).** `Stat._reconcile_modifiers` matches an
  incoming wire form against a bound modifier's FULL `to_dict()` (value
  included) — so if a remote merge (see loot-system.md) moved a stat's
  value (host: `1.0 → 1.25`), a joiner whose `intrinsic_modifiers` /
  `Entity.core_modifiers` register still says `1.0` would otherwise fail to
  match, mint a FRESH bound `1.25` instance for the stat, and leave the stale
  `1.0` sitting in the register, unbound. `StatBoard.sync_register_from_wire`
  (called on `intrinsic_modifiers` inside `read_dict`, and via the `restoring`
  signal on `Entity.core_modifiers`) moves each register entry's `value` to
  match its own wire form FIRST — privatising through
  `StatBoard.privatize_register_entry` if the entry is file-backed — so
  the reconcile then matches on the register's own instance and keeps it. The
  register entry IS the bound instance afterward; nothing needs re-pointing.
  `StatModifierCodec.merge_key(m)` (`to_dict()` minus `"value"`) is the shared
  comparison both this and `Entity.absorb_core_modifier`'s loot-merge use, so
  neither can drift on what "equivalent" means.

## No metadata-driven stat panel — wire each stat by id

`StatDef` carries only `id`, `display_name`, `description`, `value_type`,
`default_value`, `tint_color`. The `display_type`/`display_group`/`display_order`/
`parent_stat_id` fields and the `DisplayType` enum were retired in #120 with their
one consumer. HudRoot's cards hardcode which stat ids they bind, so **adding a
stat means dropping a `.tres` in `stats_system/defs/` and wiring it into the right
card by id**. Don't reintroduce `display_*` expecting something to pick it up.
Register the new id's surface (or its `hidden` reason) in `docs/domain/stat-surfaces.md`.

## Visualizer (editor plugin)

`addons/stat_board_visualizer/` — Inspector button on any `StatBoard` .tres mounts it in the "StatBoard" bottom panel. Runtime F3 overlay is `ui/stat_board_overlay/`.

- **Add modifiers** — toolbar `+` button OR drag a stat's port to another stat's port (presets as Linear `source × scale`). Disk-backed boards persist via `ResourceSaver`; runtime boards mutate in memory only.
- **Attribute/level override sliders (#861)** — an editor-only `attribute_override_bar.tscn` (no `class_name`) in the toolbar writes a stat's `base_value` in memory only, gated on `_board.resource_path != ""`, so a build's intrinsic rows can be read at any STR/DEX/INT/level spread without ever touching the `.tres` on disk; `_save_board_preserving_overrides()` restores authored values, saves, then reapplies the override so an active override can't leak into a modifier-add save.
- **Expression formula inputs are auto-derived.** `ExpressionFormula.detect_inputs(text, candidates)` uses word-boundary regex; the visualizer dialog live-validates while typing. Candidate list passed in by the caller (stat_board_graph.gd) is the board's stat ids PLUS each stat's accessor tokens (`health__current`, …) — discovered by walking `stat.accessors()` per stat — so a typed accessor parses as a legal identifier instead of failing. Decorated tokens appear in the expression-mode candidate list ONLY; they are not stats and never appear in the target / linear-source dropdowns. See #333 → Decision 7.

**`LevelGatedModifier` (#1493)** — a node-local modifier that appears at allocation level `unlock_level` (neutral element below it, authored value outright at/above, no laddering); an override of `_local_scale_override`, so the board path and `scaled_copy` both honour it. SET unsupported.
