# Stat formulas and intrinsic scaling

How a stat scales off another: the intrinsic tables on the entity and node boards, where a tuning rate lives, the CON → health model, and the formula classes with their self-descriptions. The stat and pool classes themselves are `docs/domain/stats-system.md`; the procedure for adding a knob is `docs/domain/stat-knobs-and-bins.md`; the modifier polarity/valence rules that colour a formula-bound row are `docs/domain/stats-system.md` § "Stat polarity and valence".

Intrinsics are `StatModifier` sub-resources with a `formula`, wired as `intrinsic_modifiers` on a board and applied by `apply_intrinsics()`. Keep them inline in the board `.tres` and the formula **file-backed**. Contribution = `modifier.value × formula.compute(board)`; with `value = 1` the formula reads through. A `RatioFormula` row is a line — `+1 per 20 STR` contributes `0.05 × STR` continuously and the INT target floors once at the end, so a merged loot copy (`value 1.25`) moves the step to 16 STR rather than waiting for four copies. `AttributeRules` (Attributes Panel hover) discovers these lines by scanning `intrinsic_modifiers` for `scales_with(attr_id)`; this table is documentation, not a second source of truth. **Update the table when adding or changing a row.**

## Entity board (`entity/default_entity_board.tres`)

All entities get these. Divisors (bold) are tuning values.

| Input stat | Target stat | Op | value | formula |
|---|---|---|---|---|
| `perception` | `vision_range` | INCREASE | 2 | LinearFormula(perception) — at PER=3 → +6% |
| `perception` | `sensor_range` | ADD_BASE | 1 | ThresholdFormula(perception, [3, 8, 21, 55, 149, 404, 1097, 2981, 8104, 22027]) — `floor(ln PER)`, `ceil(e^n)` per rung. PER has two jobs (vision, sensor range); WIS has one (XP/turn) |
| `wisdom` | `xp_per_turn` | ADD_BASE | 1 | RatioFormula(wisdom, **5**) |
| `dexterity` | `range` | INCREASE | 1 | LinearFormula(dexterity) — at DEX=30 → +30% |
| `dexterity` | `ranged_damage` | ADD_BASE | 1 | RatioFormula(dexterity, **20**) |
| `intelligence` | `cast_range_distance` | INCREASE | 1 | RatioFormula(intelligence, **50**) — +1% euclidean reach per 50 INT over the spell's authored `max_distance` (overlay; stat base 0 by contract) |
| `intelligence` | `cast_range_hops` | ADD_BASE | 1 | ThresholdFormula(intelligence, [50, 150, 500, 1000, 5000]) — flat +1..+5 hops over the spell's authored `max_hops` (overlay, base 0); feeds `HopRangeFinder` only, never `PropagationConfig.max_hops` |
| `intelligence` | `spell_damage` | ADD_BASE | 1 | SqrtFormula(intelligence, divisor=1) — pure sqrt transfer, no knee |
| `intelligence` | `infusion_slots` | ADD_BASE | 1 | ThresholdFormula(intelligence, [100, 1000, 10000]) — slots a cast can fill, one concept per slot |
| `intelligence` | `infusion_points` | ADD_BASE | 1 | SqrtFormula(intelligence, divisor=1) — points per slot |
| `strength` | `blade_size` | ADD_BASE | 1 | RatioFormula(strength, **40**) |
| `strength` | `blade_damage` | ADD_BASE | 1 | RatioFormula(strength, **20**) |
| `constitution` + `node_health_scaling` | `node_health` | ADD_BASE | 1 | `node_health_scaling * constitution` — the rate is a stat (see CON) |
| `constitution` + `core_health_scaling` | `health` | ADD_BASE | 1 | `core_health_scaling * constitution` — the rate is a stat (see CON) |
| `level` | `constitution` | ADD_BASE | 1 | `level_scaling.tres` (`level - 1`) — +1 CON per level |
| `max_shots_per_leaf` | `volleys_per_turn` | ADD_BONUS | 1 | LinearFormula(max_shots_per_leaf) — base 0, reads 5 by default |

## Node board (`skill_node/default_node_board.tres`)

`NodeStatBoard.intrinsic_modifiers` holds node-owned intrinsics the same way. The node board is `duplicate(true)`d per node (500–2500 per level, `.claude/rules/rendering-performance.md`), so an inlined formula forks that many ways — file-backing is non-negotiable here.

| Input stat | Target stat | Op | value | formula |
|---|---|---|---|---|
| `stake_level` (current) | `addon_slots` | ADD_BASE | 1 | `allocation_scaling.tres` — `ExpressionFormula(stake_level__current)` |
| `stake_level` (current) | `arrows_per_reload` | MULTIPLY | 1 | same file |
| `stake_level` (current) | `max_shots_per_leaf` | MULTIPLY | 1 | same file |

## Where a rate lives

**A rate goes in `value`, not in the formula string.** Baking a rate into an expression (`floor(strength / 10.0)`) splits it across two places, and raising `value` then scales the already-stepped output. `mod_per_to_vision` (2.0 × PER) and every `level_scaling` class bonus keep the rate in `value`. **Unless something other than the authored-once tuning must move the rate — then it is a stat** a CoreClass, relic, addon, aura or curse can modify through the ordinary pipeline. The decision procedure is `docs/domain/stat-knobs-and-bins.md` §1.

## CON

**CON → `health` puts its rate in a stat.** `health = 10 + core_health_scaling × CON`: the flat 10 is `pool_health`'s `base_value` and the coefficient is `core_health_scaling`, an ordinary board scalar defaulting to `1.0`. A CoreClass must be able to move it: `core_health_scaling` sizes the pool, `dealloc_damage` sizes the chip, and `nodes_lost_before_death = health / dealloc_damage` is where class identity lives (Balanced 119÷1, Glass 119÷3, Bulwark 119÷0.5). A class tunes either with an ordinary modifier — no genesis/class-param mechanism is needed. The formula is an `ExpressionFormula` with **both** ids in `inputs`, or changing the class knob won't rebind.

**CON → `node_health` does the same one pool over:** `node_health = 10 + node_health_scaling × CON`, `node_health_scaling` defaulting to `1.0`. There is no cliff: `core_class` is nullable (`GameRoot.spawn_entity` defaults it to null; coreless fixtures exist), so a fully class-side rate would have silently given them CON → 0. Both scalings are **entity-scope only** — as node-local stats they mean nothing, so don't add them to a procgen pool.

**The level→CON grant lives on the board, and only there.** The board intrinsic scales every entity's durability with level regardless of core class. `BalancedCore` contributes the +10 CON base grant but **must not** get a per-level CON entry in its `level_scaling` modifiers — that would double-count against the board intrinsic. CON is the one attribute whose level channel is board-side; STR/DEX/INT are class-side. `constitution.tres`'s `default_value` is **0**, not 10, so a bare level-1 board's `node_health` baseline stays flat 10.

CON gets **no** intrinsic targeting `armor` or `min_damage_taken`: letting CON drive `armor` produced a permanent dead zone against uninvested attackers (D-11). `test_constitution.gd` guards it.

**Procgen:** `procgen/pools/constitution.tres` is CON's `StatPack` (`archetype_stat = &"constitution"`), a **mixed pack**: CON-primary `StatPool`s drawn only by CON nodes, plus universal pools (`archetype_stat == &""`: `node_health` INCREASE, `armor` ADD_BASE, an `intelligence` INCREASE debuff `unit_value=-5, max_tier=1` whose negative cost refunds 1 budget) drawn by every node. `flatten_for_node(primary_stat)` filters per pool; the pack-level `archetype_stat` is inert. Moving a pool between primary and universal changes which nodes draw it — author it deliberately (`docs/domain/procgen-v4.md`). There is no `node_health` ADD_BASE pool: base `node_health` is `10 + CON` with `BalancedCore` granting +10 CON, so a flat draw duplicated the percent draw; only INCREASE survives, `+5–15%` (the 5% floor is because `node_health` is INT: a `+2%` roll on a base of 20 rounds away). Pinned by `test_constitution_pool.gd` and `test_constitution.gd`.

## Formula classes — pick the narrowest

| Class | Shape | Describes itself as |
|---|---|---|
| `RatioFormula(source, divisor)` | `source / divisor` — a line, no floor (ADR 0016); the INT target floors the finished total once | "per 20 STR"; a merged `value` normalises to a unit numerator (`value 4/3` over `/5` reads "+1 … per 3.75 WIS"; below one point of source it flips to "+20 … per WIS") |
| `LinearFormula(source)` | `source` | "per PER" |
| `ThresholdFormula(source, breakpoints)` | count of ascending breakpoints reached | "per ×10 INT" for a geometric ladder, else "at 50 / 150 / 500 INT" — never wrapped in "per" |
| `SqrtFormula(source, divisor)` | `floor(sqrt(max(source, 0)) / divisor)` | "√INT" at divisor 1, else "N √INT" — `describe_per()` bakes the `√` in so the default wrap reads "per 20 √INT" |
| `ExpressionFormula(text, inputs)` | anything | authored `per_phrase`, or nothing |

**No transcendental in a formula string** (`log` / `exp` / `pow` / `sin` / `cos` / `tan`; `sqrt` is fine). A step function of one stat is a `ThresholdFormula`, compared with `>=` in integer-exact arithmetic. IEEE 754 requires only `+ - * / sqrt` to be correctly rounded, so libm differs in the last bits across platforms; `floor(log_b(x))` sits exactly on a boundary at the round numbers a stat system lands on, and derived stats are recomputed on every peer, so a mixed Windows/Linux lobby desyncs silently (`floor(log(INT)/log(10))` returned 2 at INT 1000 on glibc). `mise run lint-transcendentals` fails on a new one; reasoning in `docs/domain/stat-knobs-and-bins.md` §4. A `ThresholdFormula` **saturates at `breakpoints.size()`** — extend the ladder past anything the stat can reach and pin its top in a test.

**Aggregate a bin in a stable, defined order.** Float addition is not associative; summing the same modifiers in a different order gives different last bits and peers disagree about a derived total. Godot 4 Dictionaries are insertion-ordered and insertion follows replicated command order, so this holds today — it breaks silently if a bin is sorted by a float or moved into an unordered container. Keep the order when restructuring the bin walk, and pin an aggregate against a shuffled insertion order.

**`stat / N` is a `RatioFormula`, never an `ExpressionFormula`, and never `floor(stat / N)` in either.** With `divisor` a typed field, `describe_per(value)` renders `divisor / value` and `display_coefficient(value)` renders `1` (or `value / divisor` per point once the step drops below 1), off the same two fields `compute()` multiplies, so the shown rule and the computed rule cannot disagree. `format()` hands the modifier's `value` to both; no other formula shape reads it.

**Every formula owes a one-line `per_phrase`.** `StatModifier.format()` appends it ("+1 Blade Size **per 20 STR**") and renders the modifier's `value` (the coefficient) rather than the effective value. Ratio, Linear and Threshold generate it; an `ExpressionFormula` authors one on the resource (`"×10 INT"`, `"CON × core scaling"`, `"level"`). It is not multiline — a formula-bound modifier renders as a single-Label `ModSlabRow` in a hover tooltip. Nothing derives the phrase by parsing the expression string. `test_formula_descriptions.gd` fails on an undescribed formula reachable from the shipped boards. The authored phrase is the only copy of that prose: an editor round-trip can re-serialize it as `per_phrase = null` (the stale-class-view strip in `docs/domain/godot-workflow.md`), so after any headless editor pass run `git diff '*.tres' | grep per_phrase` and restore any line that turned into `null`.

**`describe_per()` is the phrase; `describe_clause()` is what renders.** `StatModifier._with_per_clause` calls `formula.describe_clause()`; the base default wraps `describe_per()` in `" per %s"`. `ThresholdFormula` overrides `describe_clause()` alone for its non-geometric, unauthored ladder — that shape has no ratio, so `" per WIS"` would misdescribe it — and renders `" at 50 / 150 / 500 / 1000 / 5000 INT"`. `describe_per()` still returns the bare abbreviation there (non-empty, because the every-formula-described test needs an answer). A new shape needing the same escape hatch overrides `describe_clause()`, not `describe_per()`.

**A `StatDef.description`'s own "+N per D STAT" prose is a separate, hand-written field** that drifts independently of `describe_per()`. `test_stat_def_description_ratio_agreement.gd` guards every `RatioFormula`-backed intrinsic on `default_entity_board.tres` and the `entity/blocker/blocker_*_board.tres` boards: it reads the divisor off the live formula and the ratio off the target stat's description and asserts they agree, so it stays green across a retune and reds only on real drift. A description with no "per N STAT" phrase is skipped.
