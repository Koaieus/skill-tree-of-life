---
name: manage-stats
description: Add stats, modifiers, or derived scaling rules to the Skill Tree of Life stat system. Use when the user asks to add a new stat (scalar or pool), add a modifier to a stat, wire a derived/computed relationship between stats (e.g. "PER scales vision_range"), or place a modifier in the right layer (intrinsic board rule vs. entity core-class bonus vs. skill node). Covers the full implementation checklist: StatDef .tres, stat_board.gd export, default_entity_board.tres runtime instance, StatModifier + StatFormula for computed values, and the downstream homes a new stat may need (procgen pools, per-node localization).
---

# Manage Stats

You are implementing changes to the stat system in the Godot 4 project at the current working directory. Read the files listed below before touching anything. Then follow the relevant checklist.

> **This skill is process, not catalogue.** The authoritative, frequently-updated reference for *current* stat IDs, the display taxonomy, pool-def behavior, and intrinsic scaling rules is the in-repo rule **`.claude/rules/stats-system.md`**. Read it alongside this skill. Where this skill would duplicate a volatile list, it instead points there — so keep the two in sync: if you change the system in a way that affects IDs, the display contract, or the pipeline, **update `.claude/rules/stats-system.md`** (and this skill only if the *process* changed).

## Read first

These are the full picture. Read the files, not their surrounding directories.

```
stats_system/stat_board.gd          # canonical list of all stats + their @export_groups
stats_system/stat.gd                # runtime Stat base (modifier pipeline)
stats_system/stat_def.gd            # StatDef blueprint: id, display_type, display_group, parent_stat_id
stats_system/stat_modifier.gd       # StatModifier — the ONE modifier class (static OR formula-driven)
entity/default_entity_board.tres    # runtime instances of every stat — the live board
.claude/rules/stats-system.md       # authoritative reference (IDs, display contract, pool behavior, intrinsics)
```

Skim these for context if the request involves pools, derived formulas, or class identity:

```
stats_system/pool_stat_def.gd            # abstract PoolStatDef + the two virtuals
stats_system/standard_pool_stat_def.gd   # fixed-cap pool (HP, mana, AP, …)
stats_system/growable_pool_stat_def.gd   # fill-and-level pool (XP) + PostGrowMode
stats_system/cyclic_pool_stat_def.gd     # recurring threshold, carries overshoot (initiative)
stats_system/formulas/linear_formula.gd
stats_system/formulas/expression_formula.gd
entity/core/core_class.gd                # per-entity class identity bonuses (replaces the old core_modifiers)
```

---

## System overview (internalize before editing)

**Three layers of modifiers, each with a different home:**

| Layer | Lives on | Applied by | Purpose |
|---|---|---|---|
| **Intrinsic** | `StatBoard.intrinsic_modifiers` (inline in `default_entity_board.tres`) | `StatBoard.apply_intrinsics()` in `Entity._ready()` | Universal board rules: how stats on *this board* relate (e.g. PER scales vision_range). True for every entity using this board. |
| **Core class** | `Entity.core_class: CoreClass` → its `modifiers` array (`entity/core/`) | `CoreClass.apply(entity)`, called from `Entity._ready()` after intrinsics | Per-entity class identity: warrior vs glass-cannon vs tank. Different entities carry different `CoreClass` `.tres`. `BalancedCore` is the +10 STR/DEX/INT baseline. |
| **Node** | `SkillNode.modifiers` | `AllocationSystem.allocate` / `deallocate` | Acquired bonuses from the skill tree. Added/removed as the player allocates. |

> There is **no** `Entity.core_modifiers` field — it was removed. Per-entity bonuses go through a `CoreClass`. To add a class bonus, author/extend a `CoreClass` `.tres` and put `StatModifier`s in its `modifiers` array (see `.claude/rules/stats-system.md` → "Class identity modifiers"). `CoreClass.apply()` `duplicate(true)`s every entry, so the same `.tres` is safe across many entities.

**Modifier pipeline** (`Stat.get_value()`, PoE-style):
```
SET (highest priority wins, ties → last-in) → immediate return
otherwise:
  result = (base_value + Σ ADD_BASE)
         × (1 + Σ INCREASE / 100)        # INCREASE sums additively: 5×+20% = ×2.0
         × Π MULTIPLY                     # each MULTIPLY stacks independently
         + Σ ADD_BONUS
then coerced to value_type (INT rounds / FLOAT / BOOL)
```
`Operation` enum (in `stat_modifier.gd`): `0=ADD_BASE 1=INCREASE 2=MULTIPLY 3=ADD_BONUS 4=SET`.

**One modifier class — `StatModifier`** (`stats_system/stat_modifier.gd`). There is no separate `StatModifierDef` / `DerivedModifierDef` split anymore — a single class does both:
- **Static** — `formula == null` → effective value is just `value`.
- **Derived** — `formula != null` → effective value is `value * formula.compute(board)`. `value` defaults to `1.0`, so a bare formula reads straight through; set `value` to use it as a coefficient.

A formula-driven `StatModifier` carries mutable binding state (`_board`, `_bound_sources`, `_propagating`) and **must not be shared across entities** — `apply_intrinsics()` and `CoreClass.apply()` both `duplicate(true)` automatically.

**Two formula types** (`stats_system/formulas/`):
- `LinearFormula` — reads one source stat: `compute() == source.value`. The scaling coefficient is the **modifier's `value`**, not a formula field (there is no `scale_per_point`). So "+2 vision per PER" = `StatModifier{value=2, formula=LinearFormula(perception)}`.
- `ExpressionFormula` — Godot `Expression` string + `inputs: Array[StringName]` listing every stat it reads. For nonlinear math (`floor`, `log`, …) or multiple sources.

**Dirty-tracking / reactivity:** when a source stat changes, `value_changed` fires → the bound `StatModifier` re-emits → the target stat re-emits → UI/systems update automatically. A `_propagating` guard breaks A→B→A cycles. No manual refresh.

---

## Checklist: add a scalar stat

**1. Create the StatDef `.tres`** — `stats_system/defs/<stat_id>.tres`

> Omit `uid=` on hand-authored ext_resources (Godot resolves by `path=`; a stale copy-pasted UID silently nulls the field — see `.claude/rules/godot-workflow.md`). The editor backfills UIDs safely on next save.

```tres
[gd_resource type="Resource" script_class="StatDef" load_steps=2 format=3]
[ext_resource type="Script" path="res://stats_system/stat_def.gd" id="1_stat_def"]

[resource]
script = ExtResource("1_stat_def")
id = &"my_stat"
display_name = "My Stat"
description = "One sentence: what it does and what scales it."
value_type = 0          # 0=INT  1=FLOAT  2=BOOL
default_value = 10.0
display_order = 99      # higher = lower in the list
display_type = 0        # 0=BASIC 1=BAR 2=PROGRESS 3=INLINE 4=HIDDEN
tint_color = Color(0.5, 0.5, 0.5, 1)
display_group = &"combat"   # tab routing; see the display contract in stats-system.md
# parent_stat_id = &"..."   # ONLY for display_type=3 INLINE — the stat to render under
```

See `.claude/rules/stats-system.md` → "Display contract" for the tab taxonomy (`overview` / `combat` / `magic`), and when to use `display_group` vs `parent_stat_id` (INLINE).

**2. Add `@export var` to `stat_board.gd`** — inside the right `@export_group`. Current groups: Attributes, Survivability, Economy, Allocation, Turn Budget, Turn Order, Vision, Ranged, Magic, Melee, Scaling Rules. The property name **must equal** the StatDef `id` (`get_stat(id)` is `Object.get(id)`).

```gdscript
@export var my_stat: ScalarStat   ## One-line description.
```

**3. Add a runtime instance to `default_entity_board.tres`**

```tres
[ext_resource type="Resource" path="res://stats_system/defs/my_stat.tres" id="def_my_stat"]

[sub_resource type="Resource" id="scalar_my_stat"]
resource_name = "my_stat"
script = ExtResource("2_scalar")     # scalar_stat.gd, already an ext_resource in the board
definition = ExtResource("def_my_stat")
base_value = 10.0
```

Wire it in the `[resource]` block: `my_stat = SubResource("scalar_my_stat")`.

**4. Add it to hand-authored scene boards too** — see [Hand-authored boards](#hand-authored-scene-boards-the-silent-gap) below. (For a scalar a missing field just falls back to the def default — less dangerous than a pool, but still drift.)

**5. Downstream homes** — see the [decision checkpoint](#decision-checkpoint-downstream-homes-for-a-new-stat) below.

---

## Checklist: add a pool stat

**A `PoolStat` IS its own cap.** `.value` / `get_value()` returns the modifier-computed maximum; `.current` is the ephemeral game state. There are **no `*_max` sibling stats, no `max_id`, no `_max` getter** — modifiers target the pool id directly (e.g. `"mana"` raises the mana cap). This is the single biggest change from older docs.

**1. Pick the concrete def subclass** (`PoolStatDef` is abstract):

| Subclass | Use for | Key fields |
|---|---|---|
| `StandardPoolStatDef` | Fixed-cap pool (HP, mana, AP, DP, movement) | `heal_on_max_increase: bool` — bump `current` when the cap rises via modifiers so relative fill is preserved |
| `GrowablePoolStatDef` | Fill-and-level gauge (XP) | `growth_flat`, `growth_factor`, `post_grow_mode: KEEP\|RESET\|OVERFLOW` |
| `CyclicPoolStatDef` | Recurring threshold that resets on fill, carrying overshoot forward (`initiative`) | none — `on_pool_filled` does `set_current(min + excess)` |

Both inherit `min_value: int` from the base. `value_type` is INT/FLOAT only (BOOL hidden — meaningless for a cap). Read `.claude/rules/stats-system.md` → "Pool stats" for the behavior of the two virtuals (`on_pool_filled`, `on_max_increased`) and the growth math before choosing.

**None of the three fit? Author a new subclass.** The behavior split lives on `PoolStatDef` via two virtuals (`on_pool_filled(stat, excess)` fires when `current` crosses *up* to the cap; `on_max_increased(stat, delta)` fires when the pipeline raises the cap). A new pool archetype is a new `.gd` with `class_name FooPoolStatDef extends PoolStatDef` overriding the relevant virtual — that's the whole contract; `PoolStat` stays agnostic. `CyclicPoolStatDef` (third row) was added exactly this way: ~5 lines overriding `on_pool_filled`. A new `class_name` needs a **class-cache refresh** (`godot --headless --editor --quit`, then `git diff scenes/ '*.tres'`) — see gotchas. If the hook needs the stat's *own* extra state (like SP's bins), override `_custom_turn_upkeep` on the `PoolStat` subclass instead — "behaviour lives where its data lives."

**2. Create one StatDef `.tres`** — `stats_system/defs/<pool_id>.tres` (omit `uid=`):

```tres
[gd_resource type="Resource" script_class="StandardPoolStatDef" load_steps=2 format=3]
[ext_resource type="Script" path="res://stats_system/standard_pool_stat_def.gd" id="1_std_pool_def"]

[resource]
script = ExtResource("1_std_pool_def")
id = &"my_pool"
display_name = "My Pool"
description = "..."
value_type = 0
default_value = 10.0
display_order = 99
display_type = 2          # PROGRESS — default for pools
tint_color = Color(0.3, 0.5, 0.9, 1)
display_group = &"overview"
min_value = 0
heal_on_max_increase = true
```

(For a growable pool: `script_class="GrowablePoolStatDef"`, the growable script, and add `growth_flat` / `growth_factor` / `post_grow_mode`.)

Set **`per_turn_mode`** if the pool replenishes at turn start: `1` (REFILL → to cap, like AP/movement), `2` (ADD → gains its auto-derived `<id>_per_turn` companion stat, like mana/xp), or `3` (CUSTOM → the pool's `PoolStat` subclass overrides `_custom_turn_upkeep(board)`, like `skill_points`' wound-heal). Leave unset (`0` NONE) for pools with no turn-start upkeep. This is the *only* wiring needed — `StatBoard.apply_per_turn_upkeep()` sweeps every pool and each replenishes itself; do NOT edit `Entity._on_turn_started`. ADD needs the companion `<id>_per_turn` scalar to exist (a separate StatDef); CUSTOM needs a `PoolStat` subclass with the override. See `.claude/rules/stats-system.md` → "Turn-start upkeep".

**3. Add to `stat_board.gd`** — a single field, no max getter:

```gdscript
@export var my_pool: PoolStat
```

**4. Add a runtime instance to `default_entity_board.tres`** — one `[sub_resource]`, `script = ExtResource("3_pool")` (pool_stat.gd), `definition` → the def, set `current` and `base_value`. Wire `my_pool = SubResource("pool_my_pool")` in `[resource]`. Copy the `pool_health` / `pool_mana` blocks as the template.

**5. Add it to hand-authored scene boards too** — see [Hand-authored boards](#hand-authored-scene-boards-the-silent-gap) below. **A missing pool field is `null`, and a null pool can break the entity outright** (a null `initiative` means the entity never gets a turn). This step is *not* optional for pools.

**6. Turn-start upkeep** — handled by `per_turn_mode` in step 1 (above), not by hand-editing `Entity._on_turn_started`. Even bespoke upkeep (e.g. SP wound-heal, a bin transfer) is `per_turn_mode = CUSTOM` + a `PoolStat` subclass override (`_custom_turn_upkeep`), not an `_on_turn_started` if-block.

**7. Downstream homes** — see the [decision checkpoint](#decision-checkpoint-downstream-homes-for-a-new-stat).

---

## Checklist: add a modifier

A modifier is always a `StatModifier`. Static or formula-driven is one field.

**Static** (fixed bonus on a node / class / intrinsic):
```tres
[gd_resource type="Resource" script_class="StatModifier" load_steps=2 format=3]
[ext_resource type="Script" path="res://stats_system/stat_modifier.gd" id="1_mod"]

[resource]
script = ExtResource("1_mod")
stat_id = &"strength"
operation = 0           # 0=ADD_BASE 1=INCREASE 2=MULTIPLY 3=ADD_BONUS 4=SET
value = 5.0
priority = 0            # only consulted for SET
```

Place it on `SkillNode.modifiers` (allocated/removed with the node), a `CoreClass.modifiers` array (per-entity class bonus), or inline in `StatBoard.intrinsic_modifiers` (universal board rule).

**Derived (one stat scales another)** — add a `formula`:
- `LinearFormula` → `source × value`. Simple, one source, no string.
- `ExpressionFormula` → arbitrary expression, multiple sources. Use for `floor()`, `log()`, `min()`, `max()`, etc.

**Board-level intrinsic scaling rule** (applies to all entities) — inline sub_resources in `default_entity_board.tres`. The board already declares `script_linear`, `script_expr`, and the `stat_modifier.gd` script as ext_resources; reuse those ids. Real examples from the board:

```tres
# LinearFormula: +2% vision_range per PER  (value is the coefficient)
[sub_resource type="Resource" id="formula_per_to_vision"]
script = ExtResource("script_linear")
source_stat_id = &"perception"

[sub_resource type="Resource" id="mod_per_to_vision"]
script = ExtResource("12_3edt8")        # stat_modifier.gd
stat_id = &"vision_range"
operation = 1                            # INCREASE
value = 2.0
formula = SubResource("formula_per_to_vision")

# ExpressionFormula: +floor(INT/10) to the mana cap  (value defaults to 1.0 → reads through)
[sub_resource type="Resource" id="formula_int_to_mana"]
script = ExtResource("script_expr")
formula = "floor(float(intelligence) / 10.0)"
inputs = Array[StringName]([&"intelligence"])

[sub_resource type="Resource" id="mod_int_to_mana"]
script = ExtResource("12_3edt8")
stat_id = &"mana"                        # targets the pool cap directly — no "mana_max"
formula = SubResource("formula_int_to_mana")
# operation omitted → ADD_BASE (default); value omitted → 1.0
```

Then add to the array in `[resource]`:
```tres
intrinsic_modifiers = Array[ExtResource("12_3edt8")]([SubResource("mod_per_to_vision"), SubResource("mod_int_to_mana"), ...])
```

**Per-entity class rule (core):** put the `StatModifier` (with its formula sub-resource) in a `CoreClass` `.tres`'s `modifiers` array. `CoreClass.apply()` duplicates each entry, so the same `.tres` is safe on many entities.

**Godot Expression cheat-sheet** (for `ExpressionFormula`):
- Arithmetic `+ - * / **`; functions `floor ceil round abs sqrt log`(natural)`exp min max clamp`.
- Cast explicitly: `float(intelligence)`.
- `inputs` must list every stat id the formula reads.
- `log(0) == -inf` — guard with `max(1e-5, value)` (the board uses `floor(log(max(1e-5, float(wisdom))) / log(10.0))` for a base-10 log).

---

## Hand-authored scene boards: the silent gap

`default_entity_board.tres` is **not the only board.** Hand-authored level scenes embed their *own* `StatBoard` sub-resources inline (so the scene is self-contained / tweakable per-entity) — and those do **not** inherit a new stat you added to the default board. Known offenders:

- `scenes/dev_sandbox.tscn` — **two** inline boards (one per entity: Player + Enemy). Each is a `[sub_resource ... script=stat_board.gd]` with its own pool/scalar sub-resources.
- `scenes/first_level_sandbox.tscn` and any other hand-authored scene — grep before assuming: `grep -rl 'script_class="StatBoard"\|stat_board.gd' scenes/`.

For each such board, add the same `[sub_resource]` + `[ext_resource]` for the def + the `[resource]`-block assignment you added to the default board. **Each entity needs its own pool `[sub_resource]`** — pools carry per-entity ephemeral `current`, so they can't be shared between two boards.

Why it matters: a board lacking the field leaves it `null`. For a scalar, reads fall back to the def default (quiet drift). **For a pool it's worse — a null pool can break the entity** (`TurnManager.tick` skips a null `initiative`, so that entity never gets a turn). `get_pool_stats()` discovers pools by introspection, so there's no registration to forget — but the per-board instance is on you.

> Procgen content (`spawn_entity`) duplicates the *default* board, so it's covered automatically — this gap is specific to **scene-embedded** boards.

---

## Decision checkpoint: downstream homes for a new stat

Adding the stat to the board makes it *exist and scale*. A new stat is often a contender for one or both of these downstream systems — **ask before declaring done:**

**1. Procgen content (archetype-flavored stats).** *"Could a generated skill node roll this stat as a bonus?"* If yes, it needs a `TierPool` inside a `StatPack` (`procgen/pools/<archetype>.tres`):
- Pick the archetype pack (`strength.tres`, `wisdom.tres`, …) or a cross-cutting pack (`defensive.tres`, `rare.tres`, `archetype_stat = &""`).
- Pick the `role`: `PRIMARY` (stat-coherent, archetype-matched + cost-capped off-attribute), `DEFENSIVE` (always-available, no off-attribute cost cap), or `RARE` (low-weight exotic).
- Author `tiers` (value_range / cost / weight) on the `TierPool`.
- The packs are bundled into `procgen/pools/specimen_pool_set.tres`.

Don't reinvent the mechanics here — read **`docs/domain/procgen-v3.md`** (phased draw, StatPack structure, cost caps, `off_phase_op_weights`) and copy an existing pool as the template. This is the gap the skill historically missed: a new stat that's good build content but never gets a procgen pool.

**2. Per-node localization.** *"Should this stat vary per skill node, not just per entity?"* (Currently `node_health` and `range` do.) If yes, it can be localized via `SkillNode.get_local_stat(id)` / `LocalStat` (`stats_system/local_stat.gd`) — any stat id can be localized, no extra wiring needed beyond the board having the stat, but procgen pools that target it become per-node overrides. See `.claude/rules/stats-system.md` → "Local stats".

---

## Worked example: mana pool + INT scaling

Request: *"Add mana (INT pool) and mana_per_turn, with +floor(INT/10) to the mana cap and mana_per_turn base = floor(log10(INT))."* (This is what's actually in the repo today.)

1. **Two StatDef files** in `stats_system/defs/`:
   - `mana.tres` — `StandardPoolStatDef`, `display_type=2` (PROGRESS), `display_group=&"overview"`, blue tint. **No `mana_max.tres`** — the pool is the cap.
   - `mana_per_turn.tres` — `StatDef` INT scalar, `display_type=3` (INLINE), `parent_stat_id=&"mana"` so it renders as a dimmed sub-row under mana.
2. **`stat_board.gd`** (Magic group): `@export var mana: PoolStat` and `@export var mana_per_turn: ScalarStat`. No max getter.
3. **`default_entity_board.tres`**: a `pool_mana` sub_resource (`script=3_pool`, `current`/`base_value`) and a `scalar_mana_per_turn`. Wire both in `[resource]`.
4. **Two intrinsic `StatModifier`s** targeting `&"mana"` and `&"mana_per_turn"` directly, each with an `ExpressionFormula` (`floor(float(intelligence)/10.0)` and `floor(log(max(1e-5, float(intelligence)))/log(10.0))`), `value` omitted (1.0). Add both to `intrinsic_modifiers`.
5. **Turn upkeep**: `mana.tres` sets `per_turn_mode = 2` (ADD) → the upkeep sweep replenishes `mana` by `mana_per_turn` automatically. No `_on_turn_started` edit. (CoreClass `on_turn_started` is the hook for caster-specific regen on top.)
6. **Downstream**: mana lives in `intelligence.tres` StatPack as procgen content — a new magic stat would likely join it.

---

## Gotchas

- **`StatModifier` with a formula must not be shared across entities** — it holds `_board` / `_bound_sources` / `_propagating`. `apply_intrinsics()` and `CoreClass.apply()` `duplicate(true)` automatically; manual `add_modifier` callers must do it themselves.
- **Pool modifiers target the pool id, not a `_max` suffix.** `"health"` is the cap; `"health_max"` does not exist.
- **`max` / `range` are GDScript built-ins.** Never name a PoolStat property `max` (shadows `max()`); use `.value` for the cap. (The `range` stat property is fine only because no `StatBoard` method calls the global `range()`.)
- **StatBoard field name must equal the StatDef `id`.** `get_stat(id)` is `Object.get(id)` — rename both or lookup silently breaks.
- **`stat_id` on a modifier must exactly match a StatDef `id`.** Typos no-op with `push_warning("StatBoard has no stat for id X")` — check the console if a modifier isn't applying.
- **`base_value` is what modifiers layer on.** `base_value=10` + `ADD_BASE +10` = 20. Don't double-count.
- **`resource_local_to_scene` duplicates only inline `[sub_resource]` blocks, not `ExtResource` references** — that's why intrinsic modifiers/formulas are inlined in the board, not external files.
- **`ExpressionFormula._expr` is cached after first `compute()`.** If you edit `formula` at runtime (`@tool`), call `formula._invalidate()` to re-parse.
- **Pool turn-upkeep is declarative** — set `per_turn_mode` on the def (REFILL/ADD/CUSTOM), don't hand-wire `Entity._on_turn_started` (which lives on the Entity, not the single-phase TurnManager). Even the bespoke SP wound-heal is `CUSTOM` + a `PoolStat` override, so `_on_turn_started` carries no per-pool logic at all.
- **Class cache after `class_name` changes.** Only relevant if you add a *new* `class_name` (e.g. a new formula or pool-def subclass): run `godot --headless --editor --quit`, then `git diff scenes/ '*.tres'` — see `.claude/rules/godot-workflow.md`. Plain `.tres`/script-body edits don't need it.

---

## Quick reference: file paths

```
stats_system/stat_def.gd                    # StatDef blueprint (id, display_type, display_group, parent_stat_id)
stats_system/pool_stat_def.gd               # abstract PoolStatDef (+ two virtuals)
stats_system/standard_pool_stat_def.gd      # fixed-cap pool def
stats_system/growable_pool_stat_def.gd      # fill-and-level pool def (+ PostGrowMode)
stats_system/cyclic_pool_stat_def.gd        # recurring-threshold pool def (carries overshoot)
stats_system/stat.gd                        # runtime Stat base (modifier pipeline)
stats_system/scalar_stat.gd                 # concrete scalar leaf
stats_system/pool_stat.gd                   # pool: cap (.value) + ephemeral .current
stats_system/skill_point_stat.gd            # SP pool: current/wounded/staked/used buckets
stats_system/stat_modifier.gd               # THE modifier class (static OR formula-driven)
stats_system/formulas/stat_formula.gd       # abstract formula base
stats_system/formulas/linear_formula.gd     # source.value (coefficient is modifier.value)
stats_system/formulas/expression_formula.gd # Godot Expression + inputs list
stats_system/stat_board.gd                  # board: all stat exports + groups + routing
stats_system/defs/                          # one .tres StatDef per stat
entity/default_entity_board.tres            # default runtime board (all stat instances + intrinsics)
entity/entity.gd                            # apply_intrinsics() + core_class.apply() on _ready
entity/core/core_class.gd                   # per-entity class identity bonuses
procgen/pools/                              # StatPacks (procgen content) — docs/domain/procgen-v3.md
stats_system/local_stat.gd                  # per-node stat override (LocalStat)
.claude/rules/stats-system.md               # authoritative reference — KEEP IN SYNC
```
