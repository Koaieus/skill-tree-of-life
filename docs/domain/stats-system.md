# Stat system — reference

The modifier pipeline, the stat and pool classes, intrinsic scaling, and the combat-adjacent stats built on them. `.claude/rules/stats-system.md` holds the silent-failure gotchas and points here; `docs/domain/stat-knobs-and-bins.md` is the decision procedure for adding a knob or a pool bin; `docs/domain/stat-surfaces.md` says where each stat shows in the HUD; `docs/domain/stat-board-classes.md` has the board-class reasoning and measurements.

Pipeline: `(base + ADD_BASE) × (1 + INCREASE/100) × MULTIPLY + ADD_BONUS`, coerced once at the end by the stat's `value_type`. Stat IDs: `grep -h "^id = " stats_system/defs/*.tres | sort`.

## Pool stats

`PoolStat extends ScalarStat`. The stat IS the cap — `get_value()` / `.value` returns the modifier-computed maximum. `.current` is the ephemeral game state (damage/heal, not the modifier system). Modifiers target the pool id directly (`"health"`, `"action_points"`); there are no `*_max` ids.

### One door onto the cap, and a private mint

`pool.base_value = v` runs the def's cap-change policy; gameplay code has no way to move a cap without it. `Stat` declares `base_value` with `set = _set_base_value` (a named setter) so `PoolStat` can override it, even through a `Stat`-typed reference — an inline `set(v):` block cannot be overridden, so don't convert the declaration back.

| Door | Who may use it |
|---|---|
| `pool.base_value = v` | everyone — runs `_apply_max_change` |
| `pool._set_base_minted(v)` | `stats_system/` only: `SkillPointStat.claim`, `SkillPointStat.grant`, `GrowablePoolStatDef`'s growth, `PoolStat._read_base`, plus board init and `clone_live` (seeding or copying a base is not a cap change) |

### The cap-change policy

Two enums on `PoolStatDef` (`on_cap_rise` PIN/FOLLOW, `on_cap_fall` CLAMP/FOLLOW) decide what `current` does when the cap moves; FOLLOW on both also makes `PoolStat.stores_missing()` true (the pool stores damage taken). The full contract, authoring table and representation consequences are `docs/domain/stat-knobs-and-bins.md` §3.

**The clamp is an invariant, not a mode.** `current` is bounded by the cap after either policy runs. Budget that legitimately exceeds the cap is a separate bin (`SurplusPoolStat.surplus`) the policy never touches; don't "fix" either by letting `current` exceed the cap.

Authored: `on_cap_rise = FOLLOW` on `health`, `node_combat_health`, `skill_points`, `movement_points`, `action_points`, `tempo`; `PIN` on `deallocation_points`, `stake_level`, `xp`, `initiative`. `on_cap_fall = FOLLOW` on `node_combat_health` alone. The D-21 ratchet (allocating CON raises the `health` cap and hands you the delta as current HP) is `PoolStat._follow_cap_delta`, one named greppable method; the toggle is `on_cap_rise` on the def.

**The ratchet is knowingly exploitable and accepted (D-21).** The graph is the mechanics and DP is not free, so cycling territory to heal is bounded. The infinite version is closed at the other end: `deallocation_points.tres` is `PIN`, so a node granting `+1 max DP` raises the maximum without a spendable point. `test_entity_health_scaling.gd` pins both halves — don't tidy either flag.

### Def hierarchy

`PoolStatDef` is abstract; concrete pools pick one of three subclasses. `on_pool_filled(stat, excess)` fires when `current` crosses up to the cap (`excess` is the part of the inbound replenish the clamp clipped). `per_turn_mode: PerTurnMode {NONE, REFILL, ADD, CUSTOM, HOST_ADD}` declares the turn-start verb (see Turn-start upkeep).

| Def class | When to use | Adds |
|---|---|---|
| `StandardPoolStatDef` | Fixed-cap pool (HP, AP, DP, SP, movement) | nothing — the concrete "ordinary pool" choice |
| `GrowablePoolStatDef` | Gauge that grows when filled (`xp`) | `growth_flat`, `growth_factor`, `post_grow_mode` |
| `CyclicPoolStatDef` | Recurring threshold that resets on fill (`initiative`) | nothing — `on_pool_filled` does `set_current(min + excess)` |

`GrowablePoolStat` (`xp`): `on_pool_filled` banks each consumed cap into `banked`, so `total()` (`xp__total`) = `banked + current` is lifetime XP; a growable def on a plain `PoolStat` `push_error`s once. `PostGrowMode`: `KEEP` (current parks at the old cap) · `RESET` (current → min, new cap empty) · `OVERFLOW` (the level-up consumes `old_max` of the replenish and the new level starts at `min + excess`; cascades through several level-ups; XP uses it). Growth is `new_max = stat._coerce(old_max * growth_factor + growth_flat)` and **mints**, so a level-up does not run `on_cap_rise`. BOOL `value_type` is hidden from the inspector on `PoolStatDef`.

`CyclicPoolStatDef` restarts the cycle at `min + excess` — an entity that overshot keeps its lead. It is Growable's `OVERFLOW` minus the growth (Growable cannot be reused: its `on_pool_filled` bails when the cap delta is 0). `replenished` still fires at the crossing, before the carry-reset, which is how `initiative` marks an entity ready (`.claude/rules/turn-manager.md`). `per_turn_mode = NONE`: TurnManager ticks it.

**`replenished` fires in reverse chronological order across a cascade; `value_changed` doesn't.** A `replenish()` crossing several levels recurses, so each frame's `replenished.emit()` fires as the recursion unwinds — highest level first. `value_changed` fires where `base_value` is written, before the recursive call, so it stays ascending. A UI sequencer replaying a multi-level cascade builds its segments from `value_changed` snapshots, never from `replenished` order.

### SkillPointStat

`skill_points` is a `SkillPointStat`. Max is the ordinary pool cap; `current` is the spendable bucket; `wounded` and `staked` sit inside max. **`used` is derived**: `max - current - wounded - staked`.

| Method | Effect | Mints? |
|---|---|---|
| `spend(n)` / `refund(n)` | current -= n / += n | no |
| `wound(n)` / `heal(n)` | wounded += n / wounded -= n, current += n | no |
| `stake(n)` / `extract(n)` | current -= n, staked += n / reverse | no |
| `claim(n)` | `base_value += n` — max grows, current unchanged, the new SP lands in `used` (force_allocate / scripted setup) | yes |
| `grant(n)` | `base_value += n; current += n` — free SP (level-up) | yes |

Modifiers on `skill_points` bump max through the pipeline and `on_cap_rise = FOLLOW` bumps current too; `claim()` mints so the policy does not fire — that is what separates it from `grant`. Both route `current` through `set_current`, never a raw `current +=` (the raw write could leave `current` above the cap, which `available()` reports as spendable).

### Quiver

`arrows` is a `Quiver` — authored (`@export var arrows: Quiver` on `EntityStatBoard` + the sub-resource on `default_entity_board.tres`), never minted: `StatBoard._mint_stat` mints a plain `PoolStat`, so a board that reaches `arrows` through `_ensure_stat` first gets a quiver with no bins and `Entity.can_reload()` says no. `current` is the plain bin, max is capacity (`arrows.tres`: `on_cap_rise = PIN`, `per_turn_mode = NONE` — only `ReloadCommand` mints). Each special `AmmoType` banks in its own bin beside current, clamped to the `max_stock` the caller passes in (`add(id, n, max_stock)`; `Quiver` never reads the roster). `current == bins[BASE_ID]` after every `add`/`take`; a cap fall trims the plain bin only; "every arrow held" is `total_stock()` (ADR 0041). The accessor is `ammo_bins()` — `bins` is `Stat.bins: ModifierBins`, and a `func bins()` on a subclass is a parse error GUT skips silently. `_bins` is `@export` so `clone_live` carries the stock into a shadow world; `to_dict`/`read_dict` carry it over the wire. Reload stats: `arrows_per_reload` (node-owned, baked, MULTIPLY by `stake_level__current`, summed per turn-start leaf and core via `get_local_value`) and each type's `per_reload_stat_id` for specials — its `<concept>_aspect` (`poison_aspect`, `scout_aspect`), entity-flat. The type roster is `attack/ammo/ammo_type_roster.tres`, preloaded, never a directory scan.

### SurplusPoolStat

`deallocation_points` and `movement_points` are `SurplusPoolStat`. Its extra bin `surplus: int` sits outside the cap: `available() == roundi(current) + surplus`, which may exceed `.value`. Surplus is a transient one-turn budget boost, deliberately outside two systems that would stomp it: `restore_to_full()` only moves `current` (a turn-start REFILL leaves surplus alone), and the modifier pipeline never consults it, so it survives a `SET` short-circuit (a `SET cap = 0` pool with nonzero surplus is legal — an entity whose DP/MP is bought entirely with unspent AP).

Contract: **overwritten each turn, never accumulated** — write `set_surplus(n)`, never an add. `deplete()` draws surplus first (burn it or lose it). Cap changes never clamp surplus.

**Gates and budgets read `available()`, not `.current`.** `PoolStat.available()` returns `roundi(current)`; `SurplusPoolStat` adds the bin. Every `AllocationSystem` gate (including the AP one), `HighlightController._movement_budget`, `PlayerInputController`'s movement budget, `can_player_act`, `BattleSystem.launch_attack` and `ActionCluster` read `available()`. The call site must not have to know which subclass it holds, so a gate on a surplus-less pool (AP) still reads `available()` — giving AP a surplus bin is a contemplated design.

**Negative caps are undefined.** `set_current` does `clamp(v, _min_value(), cap)`; with `cap = -1` the range inverts, `current` lands at -1 and `depleted` fires on every write, including every turn-start `restore_to_full()`. Harmless for DP/MP, fatal for `health` (`depleted` → `die()`). Express a penalty as a debt bin or clamp caps at zero.

Scene-authored ownership (`owned_by = NodePath(...)`) doesn't go through `force_allocate`; `AllocationSystem.register_scene_authored_ownership()` walks the graph at `GameRoot._ready` and claims for each pre-owned node. Procgen content claims later via `force_allocate` — no double-count.

### Node combat health

The node's health is a `PoolStat` on `node_board` with id `node_health` (same id as the entity board's ScalarStat baseline, a different `Stat` class), minted off the `node_combat_health` def (`StandardPoolStatDef`, FOLLOW on both cap axes — the def and the id are different strings). The def is INT and `current` stays float storage written only whole: each of the four HP doors (`NodeCombat.take_damage`/`heal_damage`, `EntityCombat.take_pool_damage`/`heal`) floors its magnitude once via `HitPoints.land` (ADR 0017) — never floor in `Mitigation` or a formula.

Nothing pushes the cap per node: `NodeCombat._hp_pool` installs a `PoolStat.base_provider` reading the owner's baseline, so the cap is derived on read, and FOLLOW-on-both makes the pool `stores_missing()`. `SkillNode._refresh_hp_binding` is the ownership transition alone. See `docs/domain/stat-knobs-and-bins.md` § "The policy also chooses the stored representation".

## Intrinsic scaling

Intrinsics are `StatModifier` sub-resources with a `formula`, wired as `intrinsic_modifiers` on a board and applied by `apply_intrinsics()`. Keep them inline in the board `.tres` and the formula **file-backed**. Contribution = `modifier.value × formula.compute(board)`; with `value = 1` the formula reads through. A `RatioFormula` row is a line — `+1 per 20 STR` contributes `0.05 × STR` continuously and the INT target floors once at the end, so a merged loot copy (`value 1.25`) moves the step to 16 STR rather than waiting for four copies. `AttributeRules` (Attributes Panel hover) discovers these lines by scanning `intrinsic_modifiers` for `scales_with(attr_id)`; this table is documentation, not a second source of truth. **Update the table when adding or changing a row.**

### Entity board (`entity/default_entity_board.tres`)

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

### Node board (`skill_node/default_node_board.tres`)

`NodeStatBoard.intrinsic_modifiers` holds node-owned intrinsics the same way. The node board is `duplicate(true)`d per node (500–2500 per level, `.claude/rules/rendering-performance.md`), so an inlined formula forks that many ways — file-backing is non-negotiable here.

| Input stat | Target stat | Op | value | formula |
|---|---|---|---|---|
| `stake_level` (current) | `addon_slots` | ADD_BASE | 1 | `allocation_scaling.tres` — `ExpressionFormula(stake_level__current)` |
| `stake_level` (current) | `arrows_per_reload` | MULTIPLY | 1 | same file |
| `stake_level` (current) | `max_shots_per_leaf` | MULTIPLY | 1 | same file |

### Where a rate lives

**A rate goes in `value`, not in the formula string.** Baking a rate into an expression (`floor(strength / 10.0)`) splits it across two places, and raising `value` then scales the already-stepped output. `mod_per_to_vision` (2.0 × PER) and every `level_scaling` class bonus keep the rate in `value`. **Unless something other than the authored-once tuning must move the rate — then it is a stat** a CoreClass, relic, addon, aura or curse can modify through the ordinary pipeline. The decision procedure is `docs/domain/stat-knobs-and-bins.md` §1.

### CON

**CON → `health` puts its rate in a stat.** `health = 10 + core_health_scaling × CON`: the flat 10 is `pool_health`'s `base_value` and the coefficient is `core_health_scaling`, an ordinary board scalar defaulting to `1.0`. A CoreClass must be able to move it: `core_health_scaling` sizes the pool, `dealloc_damage` sizes the chip, and `nodes_lost_before_death = health / dealloc_damage` is where class identity lives (Balanced 119÷1, Glass 119÷3, Bulwark 119÷0.5). A class tunes either with an ordinary modifier — no genesis/class-param mechanism is needed. The formula is an `ExpressionFormula` with **both** ids in `inputs`, or changing the class knob won't rebind.

**CON → `node_health` does the same one pool over:** `node_health = 10 + node_health_scaling × CON`, `node_health_scaling` defaulting to `1.0`. There is no cliff: `core_class` is nullable (`GameRoot.spawn_entity` defaults it to null; coreless fixtures exist), so a fully class-side rate would have silently given them CON → 0. Both scalings are **entity-scope only** — as node-local stats they mean nothing, so don't add them to a procgen pool.

**The level→CON grant lives on the board, and only there.** The board intrinsic scales every entity's durability with level regardless of core class. `BalancedCore` contributes the +10 CON base grant but **must not** get a per-level CON entry in its `level_scaling` modifiers — that would double-count against the board intrinsic. CON is the one attribute whose level channel is board-side; STR/DEX/INT are class-side. `constitution.tres`'s `default_value` is **0**, not 10, so a bare level-1 board's `node_health` baseline stays flat 10.

CON gets **no** intrinsic targeting `armor` or `min_damage_taken`: letting CON drive `armor` produced a permanent dead zone against uninvested attackers (D-11). `test_constitution.gd` guards it.

**Procgen:** `procgen/pools/constitution.tres` is CON's `StatPack` (`archetype_stat = &"constitution"`), a **mixed pack**: CON-primary `StatPool`s drawn only by CON nodes, plus universal pools (`archetype_stat == &""`: `node_health` INCREASE, `armor` ADD_BASE, an `intelligence` INCREASE debuff `unit_value=-5, max_tier=1` whose negative cost refunds 1 budget) drawn by every node. `flatten_for_node(primary_stat)` filters per pool; the pack-level `archetype_stat` is inert. Moving a pool between primary and universal changes which nodes draw it — author it deliberately (`docs/domain/procgen-v4.md`). There is no `node_health` ADD_BASE pool: base `node_health` is `10 + CON` with `BalancedCore` granting +10 CON, so a flat draw duplicated the percent draw; only INCREASE survives, `+5–15%` (the 5% floor is because `node_health` is INT: a `+2%` roll on a base of 20 rounds away). Pinned by `test_constitution_pool.gd` and `test_constitution.gd`.

### Formula classes — pick the narrowest

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

### Stat polarity and valence

**`StatDef.lower_is_better`** (default false) marks stats where less is the win (`min_damage_taken`, `dealloc_damage`). `StatDef.is_improvement(delta)` is the one accessor (`delta < 0.0 if lower_is_better else delta > 0.0`; 0 is never an improvement). It is a delta predicate only. `DeltaChip.pop(delta, decimals, suffix, def)` consumes it (the optional `def` colours by polarity while arrow and sign stay arithmetic truth); `StatValueRow`, floaters and `StatModifier.format()` don't read it. `ModSlabRow.bind` reads `valence()` and renders a BANE as a cursed slab (`SlabRow.SlabStyle.HARMFUL`, `Emissive.HARMFUL`).

**A modifier's delta is its value's displacement from its op's neutral element.** `StatModifier.displacement_from_neutral(op, v)` is the single home of "which value is this op's no-op": `v` for ADD_BASE / ADD_BONUS / INCREASE, `v - 1` for MULTIPLY, `NAN` for SET (callers `is_nan()` first). It is static and value-taking so a procgen candidate can be judged before any `StatModifier` holds it; `GraphProcgen._is_neutral_result` routes through it.

`StatModifier.valence(board = null)` composes that with `is_improvement`: BOON / BANE / NEUTRAL / VOLATILE. VOLATILE means "no side to pick" — a SET, a sign-flipping MULTIPLY (`value <= 0`), or an unresolvable `stat_id`. Valence is holder-relative, never viewer-relative (an enemy's `-3% Dexterity` is a BANE; it never consults `ownership_bit`) and reads the same number the row next to it prints. Never re-derive `sign XOR lower_is_better` at a call site, and never `log(v)` for MULTIPLY (`log(-1.0)` is a silent NaN that renders `×-0.4` as a bane). `StatPool._get_configuration_warnings()` flags a MULTIPLY pool whose folded range reaches `<= 0`.

A stat is volatile on a read iff a modifier that read folds has `valence(board) == VOLATILE`: `Stat.is_volatile()`, `StatBoard.is_stat_volatile(id)` (entity readout; never mints), `NodeCombat.is_local_volatile(id)` / `SkillNode.is_local_volatile(id)` (node board or the owner's — the two sources `get_local_value_with` folds). No special cases, no cache.

## Parent stats

A child stat folds its ancestors' bins, never their base (mechanics in the rule). Shipped families: `damage` → `blade/spell/ranged_damage`; `attributes` → the six attributes; `status_resistance` → every `<aspect>_resistance`; `dot_stacks_per_hit` → the four `<family>_stacks_per_hit`; `aspects` → every `<concept>_aspect`. Each parent is an ordinary typed `ScalarStat` on `EntityStatBoard` (default 0, its own value never read), so a sparse board drops a family modifier like any absent stat. A node-local grant on a parent reaches a node with no child stat of its own (`bins_for`) — the Ninja's Phantom Strike is one `+5 damage`. A consumer that lists stats by id lists the child only, never child + parent.

## Local stats (per-node overrides)

**Grant routes are data on `StatDef`** (a SkillNode's two routes only; loot and core classes write a board directly):
- `local_grantable` (default false): may a node grant it onto its own board (addon `local_modifiers`, an effect's node grant)? True iff production code folds it per node. Two gated bodies: `SkillNode.add_local_modifier` (live) and `NodeCombat.add_local_modifier`'s `host == null` branch (shadow); both `push_error` and reject anything else, and the door returns its verdict so `EffectContext` never ledgers a reject. A new node-local read means flipping this flag.
- `entity_grantable` (default true): may a node grant it to its owner (`modifiers`, addon `entity_modifiers`)? False iff a strip's revoke corrupts a ledger (`skill_points`, `level`, `xp`). `StatRegistry.is_entity_grantable` vetoes a parent whose descendant is non-grantable. Both entity doors reject the whole modifier.
- `StatRegistry.check_residency()` errors at load on a def that is neither on the entity board, nor a node pool def (`NodeStatBoard.pool_def_ids()`), nor `local_grantable`. `test_stat_grant_routes.gd` lints shipped content against both flags.

`SkillNode.node_board` is a `NodeStatBoard`: owned stats baked, borrowed ones created when a node-local modifier targets them (`_ensure_local_stat(id)`) or the node is allocated (combat health pool). No `LocalStat` class — combined reads use `ModifierBins.compute()` over bins from both boards. `SkillNode.get_local_value(id)` returns the combined value without allocating (entity pass-through when the node board has no stat), falling back to `StatRegistry.get_def(id).default_value` when neither board carries it. SET tiebreak: highest priority wins, at equal priority the last source wins, and the read orders `[entity.bins, node.bins]`, so a node-local SET beats an entity SET.

**A new `StatDef` goes in `stats_system/stat_def_roster.tres`, not just `defs/`.** `StatRegistry` reads that authored roster and never scans the directory — an exported PCK rewrites every `.tres` to `.res` + remap, so a scan finds nothing and every stat lookup fails while the editor and suite stay green. `test_stat_def_roster.gd` fails if the directory and roster drift. See `docs/domain/exporting.md`.

**Node regen** (`node_healing`, `node_healing_ramp`): node-local scalars read through `get_local_value`; flat per-turn heal and the extra per consecutive undamaged turn. The stack counter is runtime state on `SkillNode` (`regen_stacks`), not a stat; there is deliberately no cap stat (the ramp stops at max HP and resets). Turn-start refill-to-full does not exist — damage persists; `SkillNode.refill()` serves the allocation path only, and the resulting dealloc/realloc full-heal is an accepted interaction (it costs DP/MP). See `docs/domain/node-hp.md`.

**Shots are runtime state, not a stat.** `max_shots_per_leaf` is the entity-board scalar (default 5, read node-locally: × `stake_level__current` intrinsic, + Watchtower `local_modifiers`), but what a leaf fired this turn lives in `SkillNode.shots_fired_this_turn`; `shots_left()` is the subtraction. It must survive a same-turn dealloc → re-allocate (allocation refills node pools) and reset at the firer's turn end even if the node changed hands. Bump it only via `mark_shot_fired(n)` from the command commit path and append the node to `Entity._fired_nodes_this_turn` in the same breath; `finish_turn` resets exactly that set. `volleys_launched_this_turn` on the Entity is the same shape against `volleys_per_turn`.

### CoreClass auras

A class's turn-start healing aura is `HealAuraEffect` (`effects/heal_aura_effect.gd`), an `AuraEffect` authored on `CoreClass.effects`. Falloff is whatever `reach`/`metric`/`distance_scale` the resource carries: Balanced pairs `HopRangeFinder(max_hops 4)` with `ExpressionScale("v - d")` over hops 0–4.

- `base` and `con_coefficient` live on the effect resource, not the board — don't add `aura_heal_*` stats.
- `v = base + con_coefficient × sqrt(CON)` is handed to `distance_scale.scale(d, bound, v)`; CON is read live off `ctx.entity.stat_board.get_value(&"constitution")` every `_on_turn_start`, never cached. `sqrt` because `node_health` grows ~linearly with CON. `max_hops` never scales.
- Hop distance is measured over the owned subgraph (`entity.navigator` via `EffectContext.navigator`) through `RangeFinder.gather`, never the global navigator and never `in_range` in a loop (`.claude/rules/graph.md`).
- A payload-channel subclass (`docs/domain/effect-system.md`): the heal is a per-turn amount, so it overrides `_on_turn_start(ctx)` rather than `_grant_to` (a deliberate no-op); `_has_payload()` reads `base > 0 or con_coefficient > 0 or distance_scale != null`.
- Heals through the damage gate, grants no ramp: `total = (node_healing + stacks × ramp) + aura_at_hop`. Clamped at 0 by an explicit `maxf(computed, 0.0)` — a negative value would be damage with no `AttackRecord` behind it (`.claude/rules/attack-timeline.md`).

## Turn-start upkeep

`Entity.begin_turn` runs, in order: pool replenishment (one declarative sweep), wound healing (bespoke), node HP refill, the class hook.

"Per turn" is four verbs, set by `PoolStatDef.per_turn_mode` (default `NONE`):

| `PerTurnMode` | Operation | Pools |
|---|---|---|
| `REFILL` | `restore_to_full()` | `action_points`, `deallocation_points`, `movement_points`, `tempo` |
| `ADD` | `current += <rate stat>.value` (clamped) | `xp` (+`xp_per_turn`) |
| `HOST_ADD` | the pool does nothing; `Entity._apply_turn_upkeep` reads `PoolStat.host_upkeep_amount` and calls `EntityCombat.heal(amount, rate_id)` | `health` (+`core_healing`) |
| `CUSTOM` | `PoolStat._custom_turn_upkeep(board)` | `skill_points` (heals `wound_heal_per_turn` wounds) |

`StatBoard.apply_per_turn_upkeep()` enumerates every `PoolStat` field (`get_pool_stats()`) and calls `pool.run_turn_upkeep(self)`. **A new pool opts into upkeep by setting `per_turn_mode` on its def, not by editing `begin_turn`.** ADD resolves its rate through `PoolStatDef.resolved_per_turn_stat_id()` and `push_warning`s if missing. `initiative` is `NONE` (TurnManager ticks it).

**ADD's rate stat is `<id>_per_turn` by convention, overridable via `per_turn_stat_id`** — `health`'s rate is `core_healing`, named for the mechanic (D-25 and the #268 balance invariant use that name). Override only for that reason. A `CoreClass.on_turn_started` hook is not the place for pool upkeep.

**Every heal enters through one door per host:** `NodeCombat.heal_damage` for `node_health`, `EntityCombat.heal` for `health`; each multiplies by `healing_received` once, `raw := true` is the only bypass, and `test/unit/test_heal_door_drift.gd` scans the tree for a `replenish`/`set_current`/`.current +=` on either pool outside the two door bodies. That is why `health` is `HOST_ADD` rather than `ADD`: an entity-hosted Wither inverts the core's own trickle exactly as it inverts node heals.

**The hook split: behaviour lives where its data lives.** `on_pool_filled` is on the **def** (cap-shape varies by def archetype); `_custom_turn_upkeep` is on the **stat** (it touches the stat's own extra state). Wound healing transfers SP from `wounded` back to `current` — a bin move, so `skill_points` is `CUSTOM`; a stray `REFILL`/`ADD` there would corrupt the `wounded`/`staked` bins (`test_per_turn_upkeep` guards it). `wound_heal_per_turn` defaults to 1.

**Fractional rates accumulate.** `SkillPointStat.wound_heal_progress` (0..1, runtime-only) banks `wound_heal_per_turn` each upkeep; once it crosses 1.0 and `wounded > 0` it heals 1 SP and drains by 1.0, so a 0.5 rate heals one SP per two turns. While `wounded == 0` it holds at a capped 1.0, so the next turn after a wound heals immediately. `wound_heal_progress_changed(progress)` feeds `turn_resources_panel.gd`'s sliver.

**`health`'s upkeep (`core_healing`)** is an integer heal, placeholder `1`/turn, **ungated and unramped**: a gate only exists to make a ramp meaningful, and a ramping out-of-combat heal rewards the camping the forced-dealloc cascade is engineered to punish. Node regen does ramp and is gated — don't unify them. `test_core_healing.gd` pins the no-gate/no-ramp contracts. Invariant (#268): `core_healing >= dealloc_damage × nodes_lost_per_turn` makes camping viable again; `1` is break-even against a 1-node chip.

**Turn end:** `Entity.finish_turn` transfers each unused action point into next turn's `deallocation_points`/`movement_points` surplus: `boost = roundi(unused_ap × ap_transfer_rate)` (ScalarStat, default 2; a Pacifist raises it, a Berserker drops it to 0). It runs at turn end because unused AP is only known then; `set_surplus` overwrites, so a turn that spends all AP self-clears the prior boost. `Entity.DEFAULT_AP_TRANSFER_RATE` is the fallback for sparse/test boards.

Then, for each owned node `SkillNode.refill()`, and `core_class.on_turn_started(self)` (default no-op).

## Effect-granted modifiers

`Effect`s grant modifiers through `EffectContext.grant(mod, target)`, which `.duplicate(true)`s once and records the handle in the `EffectInstance` ledger (`target` null = entity board, or a `SkillNode`'s `node_board`). **Provenance is the retained handle, not a field**: `StatModifier` has no `source` and `ModifierBinding.Kind` stays dormant. **Never store runtime state on an `Effect`** — one `.tres` is shared across every carrier; state goes on the per-grant `EffectInstance`. Entity-scoped node modifiers route through `SkillNode.add_entity_modifier` / `apply_entity_modifiers_to(board)`; node-scoped ones through `add_local_modifier` / `remove_local_modifier` (`docs/domain/effect-system.md`).

**`EffectContext.grant_at(mod, values, target)` writes the duplicate's leaves before granting.** Duplicate, walk `duplicate.flatten()`, SET each leaf's `.value` from `values[i]` (`PackedFloat32Array`, `flatten()` order, one already-computed value per leaf), then apply through the ordinary `grant`/`add_local_modifier` path. A write after bind is silently lost: `add_modifier` and `add_local_modifier` flatten a composite and bind each leaf, so the composite's own `value` is vestigial, and on a clone board `StatBoard._localize` hands the binder a private copy of a formula-bearing modifier so mutating the original never reaches it. One array rather than a per-leaf call because a composite is granted as one ledger handle.

**The local-scale ladder is reapplied at insert.** The ladder is linear (`1 : 2 : 3`) and MULTIPLY scales its growth part (`1 + (X−1)·ladder`) — ADR 0004. The law is `LocalScaleMutator` (`skill_node/local_scale_mutator.gd`, a stateless verb over `NodeState`); `SkillNode` keeps the `stake_level.current_changed` trigger. A modifier lands on `add_local_modifier` at its authored (al=1) value, then `SkillNode.add_local_modifier` calls `LocalScaleMutator.scale_modifier(state, m, 1, _last_allocation_level)` to bring it to the node's current level immediately. No double-scale: the ladder is floored at 1, so `al ∈ {0, 1}` both read baseline and the later per-stake-change delta composes (grant at al=3, stake to 4: ×4/3; `test_grant_at_al3_then_stake_round_trip_returns_exactly_no_double_scaling`). Scaling stays with `SkillNode`, not `AuraEffect` — an aura pre-scaling would be scaled again by the next `apply` walk — and covers every `add_local_modifier` caller, addons included. An aura scales its *distance*, never the node's allocation ladder.

A modifier that appears at allocation level K uses `LevelGatedModifier` (`stats_system/level_gated_modifier.gd`): neutral element below `unlock_level`, authored value at and above, no laddering; an override of `_local_scale_override`, so the board path and `scaled_copy` both honour it. SET unsupported.

## Dependency-cycle rejection

The formula dependency graph (`stat_id -> formula.get_input_ids()`) must stay a DAG: a cycle doesn't error or hang, it settles on a silently wrong, evaluation-order-dependent value. `test/unit/test_stat_dependency_graph.gd` checks shipped content (board intrinsics + each core class on top); `StatBoard.cycle_from(m)` (`would_cycle(m)` the bool wrapper) is the runtime half for a modifier added later (a looted formula modifier rebinding to the looter's board). It folds the candidate's edges onto everything applied and runs a DFS; `StatBoard.add_modifier` calls it as a precondition and rejects (`push_warning`, no-op) before binding any leaf, so a rejection leaves the board unchanged. **The warning reports the offending path, never `m.stat_id`** (a composite's is empty).

- **The search is rooted at the candidate's own target stats.** Any cycle through a new edge is reachable from that edge's tail; a whole-graph search would reject an innocent modifier for a cycle it had no part in. A candidate with no edges yields no roots and the live graph is never folded.
- **Edges are collected in place:** `StatModifier.collect_formula_edges(out)` defines an edge (`CompositeStatModifier` recurses); `Stat.collect_formula_edges(out)` folds its own `_modifiers`. There is deliberately no `Stat.get_modifiers()` — an escaped array lets a caller append an unbound modifier.
- **Live vs authored are two reads, on purpose:** `StatBoard.collect_formula_edges` reads what is applied; `StatBoard.adjacency_from(mods)` (static) reads an authored array, which the static test needs before anything is applied. `StatBoard.find_cycle(adjacency, roots := [])` is shared (empty roots = whole graph). Don't re-derive the DFS.
- **Runtime rejection has no notion of who should win** — the second arrival is rejected. `Entity._ready` runs `stat_board.apply_intrinsics()` then `core_class.apply(self)`, so a shipped conflict would drop the class modifier; flip the order and it voids a board intrinsic. Don't reorder, and don't treat `would_cycle` as sufficient: `test_every_authored_core_class_is_acyclic_on_top_of_the_board` discovers classes via `CoreClass.load_all()` (with a `MIN_CORE_CLASSES` vacuity floor) so a new class is enrolled automatically.
- `SkillNode.add_local_modifier` does not route through `StatBoard.add_modifier` (`get_stat` would drop a sparse-board target) but mirrors its cycle-check → bind → resolve-target sequence against `node_board`.

## Modifier packs

`CompositeStatModifier extends StatModifier` is a modifier pack, optionally atomic for loot: it bundles child modifiers into one atom for storage/authoring and flattens into its children wherever a modifier is applied or fully listed. Both uses are by reference (author one `.tres`, drop it into any `CoreClass.modifiers`):
- **Authoring reuse** (`loots_as_unit = false`): a shared batch, e.g. `stats_system/packs/attribute_baseline.tres` (+10 STR/DEX/INT, used by `balanced_core`, `basic_enemy_core`, `ninja_core`). `LootSystem._expand_for_loot` expands these into separate candidates before the lootability filter, so a mixed static/level-scaling pack filters per leaf.
- **Loot bundle** (`loots_as_unit = true`, default): a buff/debuff pair balanced only as a unit, looted all-or-nothing (`ninja_core.tres`'s `mod_budget_pack`, +2 DP / −1 SP).

**A `CoreClass` `.tres` is a leaf**: it never references another `CoreClass`; shared batches live in its typed arrays (`modifiers` via a pack, `effects` via a shared `Effect` `.tres`). Packs live in `stats_system/packs/` so `CoreClass.load_all()` never picks one up as a phantom class (D-27, `docs/adr/legacy-mvp-decisions.md`).

The whole feature is one virtual, `StatModifier.flatten() -> Array[StatModifier]` (a leaf returns `[self]`). **Keep whole** for storage/authoring/loot (`CoreClass.modifiers`, `core_location.modifiers`, loot `candidates`: one entry / one pick-N-from-M candidate). **Flatten** at the two apply seams — `StatBoard.add_modifier`/`remove_modifier` and `SkillNode.add_local_modifier`/`remove_local_modifier` — and at display sites listing every leaf: `GrantedModifiersRoot._rebuild_rows`, `LootPicker._make_card`, `SkillDustAddon.grant_mod` and `AllocationVfx` (one floater per leaf). `StatModifier.flatten_all(mods)` is the list-level helper. The composite's own `stat_id`/`operation`/`value`/`formula`/`priority` are inert (hidden via `_validate_property`); a child's `emit_changed()` reaches its Stat through normal wiring. `duplicate(true)` deep-copies `children`.

**Gotcha:** testing `m is CompositeStatModifier` while iterating a typed `Array[StatModifier]` is a parse error (script path vs `class_name`); copy into an untyped `var mods: Array` first (`test_composite_stat_modifier.gd`).

## Class identity and level

Per-entity class bonuses live on `Entity.core_class: CoreClass` (`entity/core/`), not on the board's intrinsic list. `Entity._ready` calls `core_class.apply(self)` once, installing every `CoreClass.modifiers` entry directly with **no per-entry duplication**: the same modifier instances are safe across every entity of that class because binding lives on each entity's board. `Entity.core_modifiers` is the register of modifiers permanently granted to the core, unflattened, which `LootSystem`'s draw reads; `grant_core_modifier` is the only writer. `BalancedCore` is the +10 STR/DEX/INT (and CON) baseline, plus +1 each per level, against which other classes are tuned. Procgen sandboxes pass the class to `GameRoot.spawn_entity(..., core_class)`; hand-authored scenes set it on the Entity.

**`level` is a plain INT `ScalarStat` (default 1)**, written imperatively: `Entity._on_xp_replenished` does `stat_board.level.base_value += 1`, whose `value_changed` walks the reactive path every formula source uses. `Entity.level` is a proxy onto `stat_board.level.value` / `.base_value` (fallback 1 for boards with no `level`); there is no separate counter. Level stays moddable (`+2 level` is legal); the level-up writes `base_value` so it never double-counts level modifiers.

**Per-level class bonuses are ordinary modifiers.** "+1 STR per level" is one `StatModifier` in `CoreClass.modifiers` with `value = 1.0` and `formula = level_scaling.tres` (`ExpressionFormula("level - 1")`, so level 1 sits on the authored baseline). There is no `level_up_modifiers` field and no per-level-up mutation. The shared formula is one file, so retuning the curve is a one-file edit. **Keep it file-backed**: `duplicate(true)` preserves a file-backed sub-resource's identity and copies an inline one, and the `Entity.stat_board` setter's `duplicate(true)` and `EffectContext.grant()`'s per-grant duplicate would each fork an inline formula silently.

**A `StatModifier` instance can live on N boards at once.** Both it and `StatFormula` are stateless — binding lives on `StatBoard` (`bind_modifier` / `unbind_modifier`, recomputed from `formula.get_input_ids()`). `.duplicate(true)` before `add_modifier()` is only for a genuinely independent value per grant (loot draws, addon sub-resources without `resource_local_to_scene`).

**Query level bonuses with `StatModifier.scales_with(&"level")`**, not a marker field. It asks every leaf via `flatten()`, survives duplication, and holds for a class authoring its own `ExpressionFormula("(level - 1) * dexterity")`. Two call sites with opposite signs — the HUD listing (include) and `LootSystem._is_lootable` (exclude); route a third through it. **Level-scaled mods are not lootable**: a looted copy would rebind to the looter's level, granting a scaling relic nobody designed.

`core_kill_xp` is a flat board-authored scalar `loot_system.gd` adds once on top of the territory term when the victim's own core dies (60 on `default_entity_board.tres`; 20 / 40 / 60 on the small / medium / large blocker boards).

## Damage mitigation, DoT and healing

`Mitigation.apply(raw, defender_node)` (`attack/formulas/mitigation.gd`) runs inside `SkillNode.take_damage` before HP soak: `final = max(min_damage_taken, raw.amount - armor)`. `TRUE` damage bypasses it; `raw.amount <= 0` returns 0. `armor` (default 0) and `min_damage_taken` (default 3) are board stats; a defensive core can drive `min_damage_taken` below 0 so damage heals nodes. The floor is not a cap: at `raw=1, armor=-1` you take 3. **Both are read node-locally** through `defender.get_local_value(...)`, which merges the node's bins with the owner's, so a node-scoped modifier (`bunker_addon.tscn`'s `armor ADD_BONUS +5`, a core aura) reaches the formula. A formula that takes a board instead of a node would discard node-local `armor` while `combat_readout_card.gd` still displays it — the failure mode is a stat that displays right and computes wrong.

**Forced-dealloc damage.** When a node's combat HP hits 0, `BattleSystem._on_node_depleted` runs the cascade; each cascaded node costs the defender, bypassing `Mitigation`: `skill_points.wound(1)` (SP moves `used` → `wounded`, reserved until `wound_heal_per_turn` ticks it back; hardcoded 1) and `health.deplete(dealloc_damage.value)` (default 1; a fragile-core class raises it, Glass Cannon = 3). A 5-node cascade at `dealloc_damage = 2` deals 5 wounds + 10 HP, ignoring armor.

**DoT stacks and resistance.** Each status folds through one attacker-side stacks stat and one defender-side resistance. Stacks (FLOAT, entity-scope, default 0): `poison_`/`corruption_`/`curse_`/`wither_stacks_per_hit` (parent `dot_stacks_per_hit`) plus parentless `blindness_`, `bleeding_` and `hex_stacks_per_hit`; `bleeding_resistance` (parent `status_resistance`); identity stats `bleeding_aspect` / `hex_aspect` (parent `aspects`). A `StatusDef` names its stat in `stacks_stat_id` (armor-break: blank); `StatusDef.stacks_per_hit(board, authored)` is the one fold — the authored per-hit power is a `base_add` overlay in one `get_value_with` read, never floored (1 × +49% lands 1.49); a null board, blank id or unknown stat answers the authored power. `StatusInstance.land_on` lands that once (`power_resolved`) and `AttackRecord.rebuild` marks the hit resolved so a peer replays the landed number flat.

Resistances (FLOAT fraction, default 0.0: `poison_`, `corruption_`, `curse_`, `blindness_resistance`; Wither has none) are read on the host via `get_local_value` like armor. They are a **live filter at effect time** (ADR 0031): `StatusHost.effective_power` hands every apply/tick `row − ⌈row × res − ½⌉` (half-down, clamped to `[0, row]`) while the row decays raw; `>= 1.0` blocks landing and a standing row deals 0 but decays. `DotTick.tick_damage` floors each projected tick through `HitPoints.land`. Procgen: each family lives in one attribute pack (poison DEX, corruption STR, curse CON, wither INT, blindness PER); resistance (wither excepted) rolls on blessed nodes only, ADD_BASE unit 0.05, T2–T4; the stacks INCREASE row (unit 7 → +7/+21/+49%) on blighted nodes only; `dot_stacks_per_hit` ADD_BASE on blighted WIS. See `docs/domain/status-effects.md` § "The DoT model".

**`healing_received`** (FLOAT, default 1.0) is read node-locally once at the top of `NodeCombat.heal_damage` (turn regen, the core aura, healing spells) and entity-locally once at the top of `EntityCombat.heal` (the `core_healing` HOST_ADD upkeep). `raw := true` is the only bypass. Product `<= 0` heals and cures nothing; `< 0` lands as TRUE damage flagged `DamageInstance.from_withered_heal`, the one damage path that does not set `_damaged_since_upkeep`, so the regen ramp keeps climbing and the node heals itself to death. `WitherStatus` plants an unclamped UNSCALED MULTIPLY of `1 − 0.1·stacks` on it.

## Notification batching

`StatBoard.begin_batch()` … `end_batch()` coalesces `value_changed` into one emission per stat that moved. `SkillNode.apply_entity_modifiers_to` / `remove_entity_modifiers_from` wrap their loops in one: an allocation is one logical event, and without it a node granting both `constitution` and `node_health` cascaded twice, each cascade re-syncing every owned node's HP pool (75–83% of an allocation's cost at 200 owned; `test/perf/bench_allocation_cost.gd`).

- **Every emit site calls `Stat._emit_value_changed()`**, the helper that defers to the board; a raw `value_changed.emit()` silently opts out.
- **Defers notification, never value**: `get_value()` recomputes from the bins, so a mid-batch read is correct. `PoolStat._apply_max_change` runs on the add/remove path, not off `value_changed`.
- **The flush is ordered by formula dependency depth, and that ordering is load-bearing**: emitting a source re-dirties its dependents, so one emitted too early gets a second full cascade. `end_batch` keeps the depth up during the flush and erases each stat before emitting it. Nested pairs flush once, at the outermost end.
- **Always pair it** — an unmatched `begin_batch` swallows every later notification on that board.
- Contract tests: `test/unit/test_stat_board_batch.gd`; its ordering test dirties the dependent first on purpose so it doesn't pass vacuously.

## Wire form (`to_dict` / `read_dict`)

`StatBoard.to_dict()` → `{stat_id: Stat.to_dict()}`; `Stat.to_dict()` → `{"base", "mods": [StatModifier.to_dict(), …]}`, extended down the pool chain (`PoolStat` adds `current`, `SkillPointStat` `wounded`/`staked`, `SurplusPoolStat` `surplus`). Consumed by `network/entity_snapshot.gd` for the join handshake. Deliberate, and they bite if "tidied":

- **Only accumulated state crosses.** Never `get_value()`, a `bins` field or a pool's cap — the receiver recomputes from base + modifier list. `used` is derived and absent.
- **The board encodes itself — no `Stat.get_modifiers()`.** `test_entity_snapshot.gd` asserts neither class has one.
- **`read_dict` reconciles, it does not wipe and replay.** An existing modifier whose wire form equals an incoming one is kept; only genuinely-new is minted, only genuinely-absent removed. That keeps an `EffectInstance`'s grant ledger (revoking by object identity) valid across a decode — a wipe strands every effect's handle and its buff sticks forever. Matching walks `_modifiers` newest-first, because in `EntitySnapshot`'s second pass a node-sourced effect's fresh grant sits next to pass 1's decoded copy and the later one is the ledgered handle.
- **`PoolStat._read_base` mints and `current` is restored raw.** Transporting a cap is not a cap change, so the def's rise/fall policy must not move the restored `current`; `current` skips `set_current` because its crossings would fire `on_pool_filled` (a full `xp` pool levels the entity up on arrival) and `depleted` (a `health` pool at 0 kills it). `current_changed` / `value_changed` are emitted by hand so UI still updates.
- **`StatBoard.read_dict` pre-syncs the register before the reconcile.** `Stat._reconcile_modifiers` matches against a bound modifier's full `to_dict()` (value included); after a remote loot merge moved a value (`1.0 → 1.25`), a joiner whose `intrinsic_modifiers` / `Entity.core_modifiers` still says `1.0` would mint a fresh bound `1.25` and leave the stale one unbound. `StatBoard.sync_register_from_wire` (on `intrinsic_modifiers` inside `read_dict`, and via the `restoring` signal on `Entity.core_modifiers`) moves each entry's `value` to match its wire form first — privatising through `StatBoard.privatize_register_entry` if file-backed. `StatModifierCodec.merge_key(m)` (`to_dict()` minus `"value"`) is the shared comparison with `Entity.absorb_core_modifier`'s loot-merge.

## BOOL stats

`StatDef.ValueType.BOOL` fits a stat whose only question is "granted or not" and a magnitude would mislead; `deflection` is the only one. `armor`, `blunting`, `spike_regen`, `swing_drag` stay INT/FLOAT. `deflection` is read as `bool(sn.get_local_value(&"deflection"))` in exactly one place, `MeleeAttackPlan.build_obstacle_field`. `Stat._coerce` returns a real GDScript `bool` (`v != 0.0`). `ModifierPoolEntry`'s BOOL branch clamps a rolled ADD_BASE/ADD_BONUS to `1.0`/`0.0`; `deflection` is addon-authored and in no procgen pool, so don't build a pool entry to reach it. **The no-mint invariant** holds across the sparse node-local defender tier (`deflection`, `swing_drag`, `blunting`, `spike_regen`): reading one off a node that never had the granting addon returns the def default and mints nothing (`test_defender_stat_no_mint.gd`).

Display has two type-aware doors: `StatDef.format_number(BOOL, v)` → `"True"`/`"False"` (the direct-value path, `StatValueRow`), and `StatModifier._format_value`, which renders a BOOL modifier as a bare trait line — the stat's display name alone, no sign or number, whatever the op (`Deflection`, not `+1 bonus Deflection`). INCREASE / MULTIPLY on a BOOL stat is a content error: it `push_warning`s and still renders the bare line. `contribution_text` (the stat-name-omitted "+10"/"×1.5" form used by the visualizer and per-leaf allocation floaters) is not type-aware.

## Visualizer (editor plugin)

`addons/stat_board_visualizer/` — an Inspector button on any `StatBoard` `.tres` mounts it in the "StatBoard" bottom panel; the runtime F3 overlay is `ui/stat_board_overlay/`.
- **Add modifiers** with the toolbar `+` or by dragging one stat's port to another's (presets as Linear `source × scale`). Disk-backed boards persist via `ResourceSaver`; runtime boards mutate in memory only.
- **Attribute/level override sliders**: an editor-only `attribute_override_bar.tscn` writes a stat's `base_value` in memory, gated on `_board.resource_path != ""`, so intrinsic rows can be read at any STR/DEX/INT/level spread without touching the `.tres`; `_save_board_preserving_overrides()` restores authored values, saves, then reapplies the override.
- **Expression formula inputs are auto-derived** by `ExpressionFormula.detect_inputs(text, candidates)` (word-boundary regex, live-validated in the dialog). Candidates are the board's stat ids plus each stat's accessor tokens (`health__current`, …) from `stat.accessors()`, in the expression-mode list only — they are not stats and never appear in the target/linear-source dropdowns.
