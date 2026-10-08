# Stat system — long-form reference

Moved verbatim out of `.claude/rules/stats-system.md` to keep that rule under its size budget; the rule keeps a one-line pointer per section.


## Pool stats

`PoolStat extends ScalarStat`. The stat IS the cap — `get_value()` / `.value` returns the modifier-computed maximum. `.current` is the ephemeral game state (damage/heal, not the modifier system). Modifiers always target the pool id directly (e.g. `"health"`, `"action_points"`); there are no `*_max` sibling stats or IDs.

### One door onto the cap, and a private mint (#555, supersedes D-31's two doors)

**`pool.base_value = v` runs the def's cap-change policy.** That is the whole
API — there is no `set_base_ratcheted` any more, and no way for gameplay code to
move a cap without the configured policy firing.

It works because `Stat` declares `base_value` with **`set = _set_base_value`**
(a named setter function), not an inline `set(v):` block: an inline block cannot
be overridden, a named one is an ordinary virtual method, so `PoolStat` overrides
it. Verified — the override fires even through a `Stat`-typed reference, and
`base_value = v` inside the setter assigns without re-entering it.
**Don't convert that declaration back to an inline block.**

| Door | Who may use it |
|---|---|
| `pool.base_value = v` | everyone — runs `_apply_max_change` |
| `pool._set_base_minted(v)` | **`stats_system/` only.** Four mint sites: `SkillPointStat.claim`, `SkillPointStat.grant`, `GrowablePoolStatDef`'s growth, `PoolStat._read_base` — plus board init and `clone_live`, where seeding or copying a base is not a cap *change* |

**Why the inversion mattered:** before #555 the plain assignment was the *bypass*,
so every new call site silently skipped the pool's own configuration — a wrong
number, no error. Worked example: `docs/domain/stat-knobs-and-bins.md` § "How
this bit us (#346)".

### The cap-change policy: two enums on `PoolStatDef`

`heal_on_max_increase: bool` is **gone**. It was a degenerate two-value enum on
one subclass, answering the same question `GrowablePoolStatDef.post_grow_mode`
answers with three values on a sibling, while the cap-*fall* half was hardcoded
and the whole thing was skippable.

| field | values | meaning |
|---|---|---|
| `on_cap_rise` | `PIN` (default) / `FOLLOW` | does `current` rise with the cap |
| `on_cap_fall` | `CLAMP` (default) / `FOLLOW` | does `current` drop with the cap even when it had headroom |

**The clamp is an INVARIANT, not a mode.** `current` is bounded by the cap after
either policy runs, and nothing can switch that off. Budget that legitimately
exceeds the maximum is a **separate bin** — `SurplusPoolStat.surplus`
(`deallocation_points`, `movement_points`), which sits outside the cap and which
the cap-change policy must never touch. Those two facts coexist; don't "fix"
either by letting `current` exceed the cap.

Authored today: `on_cap_rise = FOLLOW` on `health`, `node_combat_health`,
`skill_points`, `movement_points`, `action_points`, `tempo`; `PIN` on
`deallocation_points`, `stake_level`, `xp`, `initiative`. `on_cap_fall = FOLLOW`
on `node_combat_health` alone; every other pool CLAMPs. **FOLLOW on both axes is
not just two policies** — it is the discriminator `PoolStat.stores_missing()`
reads to store damage taken instead of an absolute `current` (#660).

**The D-21 ratchet is now `PoolStat._follow_cap_delta`** — still one named,
greppable method as D-26 requires, and now signed (it serves both directions).
The toggle D-26 wants findable is `on_cap_rise` on the def.

**`StandardPoolStatDef` is now deliberately empty** — the concrete "ordinary
pool" choice, nothing more. `PoolStatDef` is abstract, so every def still picks a
subclass.

### Def hierarchy

`PoolStatDef` is abstract — concrete pools pick one of two subclasses, never the base directly. PoolStat stays agnostic to which subclass it holds; fill behaviour is delegated through one virtual on the base:

- `on_pool_filled(stat, excess)` — fires when `current` crosses up to the cap. `excess` is the amount of the inbound replenish that was clipped by the cap-clamp.

Cap-change behaviour is **authored data**, not a virtual — `on_cap_rise` / `on_cap_fall` above (#555). `on_max_increased` is gone.

The base also carries `per_turn_mode: PerTurnMode {NONE, REFILL, ADD, CUSTOM}` — how the pool replenishes at turn start (`CUSTOM` dispatches to a `PoolStat` virtual). See "Turn-start upkeep" below. Default `NONE`.

| Def class | When to use | Adds |
|---|---|---|
| `StandardPoolStatDef` | Fixed-cap pool (HP, AP, DP, SP, movement) | **nothing** — cap-change policy moved up to `PoolStatDef` in #555 |
| `GrowablePoolStatDef` | Gauge that grows when filled (XP today; any future "fill-and-level" pool) | `growth_flat: float`, `growth_factor: float`, `post_grow_mode: PostGrowMode` |
| `CyclicPoolStatDef` | Recurring threshold that resets on fill, carrying overshoot forward (`initiative` today) | nothing — `on_pool_filled` just does `set_current(min + excess)` (no growth) |

`xp` is a `GrowablePoolStat` (PoolStat subclass): `GrowablePoolStatDef.on_pool_filled` banks each consumed cap into `banked`, so `total()` (`xp__total`) = `banked + current` is lifetime XP; a growable def on a plain `PoolStat` `push_error`s once.

`CyclicPoolStatDef` is the cap-as-recurring-threshold archetype: filling does NOT grow the cap and does NOT leave `current` parked at the cap — it restarts the cycle at `min + excess`, so the "deduct one cap's worth on cross" is implicit and an entity that overshot more keeps that lead. It's Growable's `OVERFLOW` post-grow path minus the growth (Growable can't be reused — its `on_pool_filled` bails when the cap delta is 0). The `replenished` signal still fires at the crossing (before the carry-reset), which is how `initiative` marks an entity ready — see `.claude/rules/turn-manager.md`. `per_turn_mode = NONE` (it's tick-driven by TurnManager, not the turn-start sweep).

`PostGrowMode` (Growable only): `KEEP` (current parks at old cap, new headroom = delta) · `RESET` (current → min_value, new cap empty) · `OVERFLOW` (level-up consumes `old_max` worth of replenish; new level starts at `min_value + excess` — cascades naturally through multiple level-ups if the inbound replenish was huge). XP uses `OVERFLOW`.

Growth math: `new_max = stat._coerce(old_max * growth_factor + growth_flat)` — coercion is via the stat's `value_type`, so int pools snap and float pools don't. Growth **mints** (`_set_base_minted`) so a growable pool's level-up does NOT run `on_cap_rise` — same deliberate pattern as `SkillPointStat.claim()`. BOOL `value_type` is hidden from the inspector via `_validate_property` on `PoolStatDef` — meaningless for a cap.

### `replenished` fires in REVERSE chronological order across a cascade — `value_changed` doesn't

A `replenish()` crossing multiple levels recurses, so each frame's
`replenished.emit()` fires as the recursion *unwinds* — the highest level first,
the level actually reached first last. `value_changed` fires at the point
`base_value` is written, before the recursive call, so it stays in true ascending
order.

**How to apply:** anything replaying a multi-level cascade in order (a UI
sequencer chaining "fill → grow → fill" per level) must build its segments from
`value_changed` snapshots, never from the order of `replenished` calls.

`skill_points` is `SkillPointStat` (PoolStat subclass). Max is the canonical PoolStat value (base + modifier pipeline). `current` is the spendable bucket; `wounded` and `staked` are two extra book-keeping buckets sitting *inside* max. **`used` is derived**: `max - current - wounded - staked` — SP locked into currently-allocated nodes. Operations:

| Method | Effect | Mints? |
|---|---|---|
| `spend(n)` | current -= n (used derives +n) | no |
| `refund(n)` | current += n (used derives -n) | no |
| `wound(n)` | wounded += n (used derives -n) | no |
| `heal(n)` | wounded -= n; current += n | no |
| `stake(n)` | current -= n; staked += n | no |
| `extract(n)` | staked -= n; current += n | no |
| **`claim(n)`** | `base_value += n` — max grows, current unchanged, the new SP lands in `used`. Equivalent to "grant(n) then spend(n)" collapsed atomically. Use for force_allocate / scripted setup. | **yes** |
| **`grant(n)`** | `base_value += n; current += n` — mints free SP (level-up). | **yes** |

Modifiers on `skill_points` behave like modifiers on any other PoolStat — they bump max via the pipeline, and `on_cap_rise = FOLLOW` on the def causes modifier-driven max changes to also bump current. `claim()` **mints** so the policy does NOT fire — that's exactly what distinguishes it from grant. Both route `current` through `set_current`, never a raw `current +=`: `base_value += n` does not imply the *cap* moved by `n`, and the raw write could leave `current` above the cap, which `available()` reports as spendable (#555).

`arrows` is `Quiver` (PoolStat subclass, #955) — **authored, never minted.** `@export var arrows: Quiver` on `EntityStatBoard` + the sub-resource on `default_entity_board.tres`, exactly like `skill_points`: `StatBoard._mint_stat` mints a plain `PoolStat`, so a board that reaches `arrows` through `_ensure_stat` first (a hand-built board with no instance) gets a quiver with no bins and `Entity.can_reload()` says no. `current` = the **plain** bin, max = capacity (`arrows.tres`, `on_cap_rise = PIN` so a capacity modifier never gifts arrows, `per_turn_mode = NONE` so nothing refills it — only `ReloadCommand` mints); each special `AmmoType` banks in its own bin *beside* current, clamped to its `max_stock`, which the caller passes in (`add(id, n, max_stock)` — `Quiver` never reads the roster and keeps its own `BASE_ID`). `current == bins[BASE_ID]` after every `add`/`take`; a cap **fall** trims the plain bin only; "every arrow held" is `total_stock()` (ADR 0041). The accessor is `ammo_bins()` — `bins` is `Stat.bins: ModifierBins`, the modifier pipeline's, and a `func bins()` on a subclass is a parse error that GUT skips silently. `_bins` is `@export` only so `clone_live` (`duplicate(true)`) carries the stock into a shadow world; `to_dict`/`read_dict` carry it over the wire. Minting stats: `arrows_per_reload` (node-owned + baked, MULTIPLY by `stake_level__current`, summed per turn-start leaf ∪ core via `get_local_value`) and the type's `per_reload_stat_id` for specials — its `<concept>_aspect` (`poison_aspect`, `scout_aspect`), entity-flat (#1248). The type roster is `attack/ammo/ammo_type_roster.tres` — preloaded, never a directory scan.

`deallocation_points` and `movement_points` are `SurplusPoolStat` (PoolStat subclass, #152/#156). Unlike SkillPointStat's bins which sit *inside* max, its one extra bin — `surplus: int` — sits **outside** the cap:

```
available() == roundi(current) + surplus     # may exceed .value
```

Surplus is a **transient budget boost** (extra DP/MP for one turn). It's deliberately outside two systems that would otherwise stomp it:
- **`restore_to_full()`** only moves `current` against the cap, so a turn-start REFILL leaves surplus untouched (that's the whole point — a turn-start cap-modifier boost would arrive *after* the refill that fills it).
- **The modifier pipeline** never consults it — no `heal_on_max_increase`, and crucially it survives a `SET`-short-circuit. A `SET cap = 0` pool with nonzero surplus is a legal, meaningful state (an entity whose entire DP/MP budget is bought with unspent AP); a cap-modifier design can't represent it.

Contract: **overwritten each turn, never accumulated** — write it with `set_surplus(n)` (never an `add_surplus`, which would let an idle entity compound it). `deplete()` draws **surplus-first** (burn-it-or-lose-it: the boost is spent on travel or wasted; ordinary budget survives an idle turn). Cap changes never clamp surplus.

**Gates and budgets must read `available()`, not `.current`.** `PoolStat.available()` (base) returns `roundi(current)`; `SurplusPoolStat` overrides it to add the bin. `AllocationSystem` (every gate, including the AP one), `HighlightController._movement_budget` and `PlayerInputController`'s movement budget read `available()` and honour surplus polymorphically without knowing the subclass. A gate reading `.current` would grant cells the player can't spend.

Only `deallocation_points` and `movement_points` are `SurplusPoolStat` today; `action_points` is a plain pool, where the two forms agree. That is exactly why the AP gates in `PlayerInputController.can_player_act`, `BattleSystem.launch_attack` and `ActionCluster` sat on `.current` unnoticed until the 2026-08-14 audit — and why this paragraph named them as compliant examples while they weren't. They read `available()` now. **The point of the rule is that the call site must not have to know which subclass it holds**, so don't "optimise" one back to `.current` on the grounds that its pool has no surplus bin *yet*: giving AP a surplus bin is a design the surplus section above explicitly contemplates ("an entity whose entire DP/MP budget is bought with unspent AP").

**Negative caps are undefined — don't reach for them.** `PoolStat.set_current` does `clamp(v, _min_value(), cap)`; with `cap = -1` the range inverts and `clamp` returns the cap, so `current` lands at `-1` (below floor) and `depleted` fires on *every* write, including every turn-start `restore_to_full()`. Harmless for DP/MP (nothing listens), fatal for `health` (`depleted` → `die()`). Express a penalty as a debt bin with real semantics, or clamp caps at zero — a real `min_value` change is its own issue.

Scene-authored ownership (e.g. dev_sandbox `owned_by = NodePath(...)`) doesn't go through `force_allocate`, so `AllocationSystem.register_scene_authored_ownership()` walks the graph at GameRoot._ready and claims for each pre-owned node. Procgen content runs later and claims via force_allocate — no double-count.


## Intrinsic scaling (node board)

Same field, one level down: `NodeStatBoard.intrinsic_modifiers` (`skill_node/default_node_board.tres`) holds node-owned intrinsics the same way the entity table above does — modifier inline on the board, formula file-backed. The node board is `duplicate(true)`d **per node** (500–2500/level, `.claude/rules/rendering-performance.md`) rather than per entity, so an inlined formula here forks that many ways instead of a handful — treat file-backing as non-negotiable for this table, not just good practice.

| Input stat | Target stat | Op | value | formula |
|---|---|---|---|---|
| `stake_level` (current) | `addon_slots` | ADD_BASE | 1 | `allocation_scaling.tres` — `ExpressionFormula(stake_level__current)` |
| `stake_level` (current) | `arrows_per_reload` | MULTIPLY | 1 | `allocation_scaling.tres` — `ExpressionFormula(stake_level__current)` (#955) |
| `stake_level` (current) | `max_shots_per_leaf` | MULTIPLY | 1 | `allocation_scaling.tres` — `ExpressionFormula(stake_level__current)` (#956) |

### Formula classes — pick the narrowest one (#289)

| Class | Shape | Describes itself as |
|---|---|---|
| `RatioFormula(source, divisor)` | `source / divisor` — a LINE, no floor (#891, ADR 0016); the INT target floors the finished total once | "per 20 STR" (generated); a merged `value` normalises to a unit numerator — `value 4/3` over `/5` reads "+1 … per 3.75 WIS", and below one point of source it flips to "+20 … per WIS", never "+1 per 0.05" |
| `LinearFormula(source)` | `source` | "per PER" (generated) |
| `ThresholdFormula(source, breakpoints)` | count of ascending breakpoints reached | "per ×10 INT" for a geometric ladder, else "at 50 / 150 / 500 INT" — names the ladder, never wrapped in "per" (#773) |
| `SqrtFormula(source, divisor)` | `floor(sqrt(max(source, 0)) / divisor)` — pure sqrt transfer (#760, made knee-free by #776) | "√INT" at divisor 1, else "N √INT" (generated) — `describe_per()` bakes the `√` in so the default `" per %s"` wrap reads "per 20 √INT", never the bare "per N INT" a linear rate would claim |
| `ExpressionFormula(text, inputs)` | anything | authored `per_phrase`, or nothing |

**No transcendental in a formula string — `log` / `exp` / `pow` / `sin` / `cos` / `tan`;
`sqrt` is fine (#547).** A step function of one stat is a `ThresholdFormula`, whose
`breakpoints` are compared with `>=` in integer-exact arithmetic. `floor(log(INT)/log(10))`
returned **2 at INT 1000** on glibc — `log(1000.0)` is one ulp under `3 * log(10.0)` — and
that is not a bug to wait out: IEEE 754 requires only `+ - * / sqrt` to be correctly
rounded, so every platform's libm differs in the last bits, and `floor(log_b(x))` sits
exactly on a boundary at the round numbers a stat system lands on constantly. Derived
stats are recomputed on **every peer** rather than sent, so the next one desyncs a mixed
Windows/Linux lobby silently. `mise run lint-transcendentals` fails on a new one.
A `ThresholdFormula` **saturates at `breakpoints.size()`** — extend the ladder past
anything the stat can reach, and pin its top in a test.

**Same reason, second rule: aggregate a bin in a STABLE, DEFINED order.** Float
addition is not associative, so summing the same modifiers in a different order gives
different last bits and two peers disagree about a node's derived total. Godot 4
Dictionaries are insertion-ordered and insertion follows replicated command order, so
this holds today — it breaks silently the moment a bin is sorted by a float or moved
into an unordered container. Relevant the instant anyone restructures the bin walk for
perf (#470): keep the order, and pin an aggregate against a shuffled insertion order.

**`stat / N` must be a `RatioFormula`, never an `ExpressionFormula` — and never
`floor(stat / N)` in either (#891).** A ratio is a line; the stat floors. With
`divisor` a typed field, `describe_per(value)` renders `divisor / value` and
`display_coefficient(value)` renders `1` (or `value / divisor` per point once the
step drops below 1), both off the same two fields `compute()` multiplies, so the
shown rule and the computed rule cannot disagree — the property `ThresholdFormula`
reads its multiplier off `breakpoints` for the same reason. `format()` hands the
modifier's `value` to both; no other formula shape reads it.

**Every formula owes a one-line `per_phrase`.** `StatModifier.format()` appends it —
"+1 Blade Size **per 20 STR**" — and renders the modifier's `value` (the coefficient)
rather than the effective value, because the clause now carries the variable part. Ratio,
Linear and Threshold generate the phrase; an `ExpressionFormula` must author one on the resource
(`"×10 INT"`, `"CON × core scaling"`, `"level"`). It is deliberately **not
multiline** — a formula-bound modifier renders as a single-Label glass slab (`ModSlabRow`)
in a hover tooltip, and prose would blow the line budget. Nothing may derive the phrase by
parsing the expression string. `test_formula_descriptions.gd` fails on an undescribed
formula reachable from the shipped boards.

**A `StatDef.description`'s own "+N per D STAT" prose is a SEPARATE, hand-written
field from `describe_per()`/`format()` above — it drifts independently, and did**
(#825: `blade_size.tres` said "per 10 STR" while `formula_str_to_blade_size` had
long since moved to `divisor = 20.0`, sizing an AI budget pass 2x optimistic).
`test/unit/test_stat_def_description_ratio_agreement.gd` guards every
`RatioFormula`-backed intrinsic on `default_entity_board.tres` and the four
`entity/blocker/blocker_*_board.tres` — it reads the divisor off the live formula
and the ratio off the target stat's `description` and asserts they agree, so it
stays green across a retune (divisors are owner-tuned, e.g. #776) and only reds
on real drift. A description with no "per N STAT" phrase is skipped, not failed
— not every stat spells its ratio out in prose. The durable fix — compose
`description` from the formula instead of hand-writing the ratio, so this class
of drift can't recur — is proposed but not built (bigger than #825, touches the
tooltip path).

**`describe_per()` is the phrase; `describe_clause()` (#773) is what actually
renders.** `StatModifier._with_per_clause` calls `formula.describe_clause()`, not
`describe_per()` directly — the base class's default `describe_clause()` just
wraps `describe_per()` in `" per %s"`, which is right for every ratio/linear/
authored shape. `ThresholdFormula` overrides `describe_clause()` alone (not
`describe_per()`) for its non-geometric, unauthored ladder: that shape has no
ratio, so `" per WIS"` would misdescribe it as a rate it doesn't have.
`describe_per()` still returns the bare abbreviation there — kept non-empty
on purpose, since `test_every_board_intrinsic_formula_is_described` requires
every shipped formula to answer *something* — but `describe_clause()` renders
the ladder itself instead: `" at 50 / 150 / 500 / 1000 / 5000 INT"`, no "per"
anywhere. A future formula shape that needs the same escape hatch overrides
`describe_clause()`, not `describe_per()`.

**An authored `per_phrase` is the only copy of that prose — an editor round-trip has
already eaten all three once.** `fe0c625` re-serialized `level_scaling.tres` and
`default_entity_board.tres` with `per_phrase = null`, silently un-describing three
`ExpressionFormula`s (4 red tests, no runtime error — it's the stale-class-view strip
that [godot-workflow.md](../../docs/domain/godot-workflow.md) documents). Nothing regenerates these strings.
**How to apply:** after any `godot --headless --editor --quit`, add
`git diff '*.tres' | grep per_phrase` to the usual post-refresh diff check, and restore
any line that turned into `null`.

`AttributeRules` (Attributes Panel hover) now **discovers** these lines by scanning
`intrinsic_modifiers` for `scales_with(attr_id)` — it holds no rule text of its own, so
this table is documentation, not a second source of truth.

**Put a rate in `value`, not in the formula string.** Most expression-formula intrinsics above bake their rate into the expression (`floor(strength / 10.0)`) and leave `value` at its 1.0 default. That still works — the knob exists on every modifier — but it splits the rate across two places, and turning `value` up on a `floor(X/10)` formula scales the already-*stepped* output rather than the rate. Prefer the rate in `value`; `mod_per_to_vision` (2.0 × PER) and every `level_scaling` class bonus follow it.

**…unless something other than #268 must move the rate — then it's a STAT.** `value` is authored-once tuning; a *stat* can be moved at runtime by a CoreClass, relic, addon, aura or curse through the ordinary pipeline. Both CON intrinsics take this branch (see the next two paragraphs), and the decision procedure for which shape a new knob wants is `docs/domain/stat-knobs-and-bins.md` §1.

**CON → `health` puts its rate in a *stat*, not in `value` (D-26, #276).** `health = 10 + core_health_scaling × CON`: the flat 10 is `pool_health`'s `base_value` (baked for now — D-26 defers making it a stat to #279's authoring problem), and the coefficient is `core_health_scaling`, an ordinary board scalar defaulting to `1.0`. It's a stat rather than a modifier `value` because a **CoreClass must be able to move it** — `core_health_scaling` sizes the pool, `dealloc_damage` sizes the chip, and `nodes_lost_before_death = health / dealloc_damage` is where class identity lives (Balanced 119÷1, Glass 119÷3, Bulwark 119÷0.5). Both are plain board stats, so a class tunes either with an ordinary modifier — **no genesis/class-param mechanism is needed or wanted here.** Consequence for the formula: it's an `ExpressionFormula` with **both** ids in `inputs`, or changing the class knob won't rebind.

`core_health_scaling` is **entity-scope only** — as a node-local stat it means nothing (D-26 surfaced this; #287 is the open decision). Don't add it to a procgen pool.

**CON → `node_health` does the same thing, one pool over (#298).** `node_health = 10 + node_health_scaling × CON`, with `node_health_scaling` an ordinary board scalar defaulting to `1.0`. This **settled #298** — its two proposed options (a `CoreClass` genesis param, or a board baseline plus a class delta) were both dropped in favour of the D-26 precedent, because a class tuning it needs no new mechanism and there is **no cliff**: `core_class` is nullable (`GameRoot.spawn_entity` defaults it to null, `Entity._ready` guards on it) and coreless entities really exist (several fixtures), so a fully class-side rate would have silently given them CON → 0. Same `inputs`-must-list-both-ids consequence as `health`. Per-class values remain a #268 pass — don't invent them. `node_health_scaling` is likewise entity-scope only.

**The D-21 ratchet lives in `PoolStat._follow_cap_delta`.** Allocating CON raises the `health` cap *and* hands you the delta as current HP, so a player can cycle territory to heal. That is **knowingly exploitable and accepted** (D-21) — the graph *is* the mechanics, and DP is not free, so the ratchet is bounded. D-26 requires the grant to stay one named, greppable method rather than being inlined into an allocation path, so the toggle is findable when it's revisited; `health.tres` carries `on_cap_rise = 1` (FOLLOW) deliberately. The *infinite* version is closed at the other end: `deallocation_points.tres` sets `on_cap_rise = 0` (PIN), so a node granting `+1 max DP` raises the maximum **without** granting a spendable point. Both halves are pinned by `test_entity_health_scaling.gd` — don't "tidy" either flag. The recorded-but-not-adopted alternative (voluntary dealloc subtracts the delta and is illegal if lethal; forced dealloc reduces max only) is the first thing to reach for if the ratchet misbehaves.

**CON (D-11/D-12/D-14, #269) — the level→CON grant lives on the board, and only there (user decision, 2026-07-24).** D-15 originally named `BalancedCore` as its home, mirroring `+1 STR/DEX/INT per level`. It was settled the other way: the board intrinsic means **every** entity's durability scales with level regardless of core class, which is the asymmetry #269 existed to fix. **`BalancedCore` therefore contributes the +10 CON *base* grant (#271) but must NOT get a per-level CON entry in its `level_scaling` modifiers** — that would double-count against the board intrinsic. CON is the one attribute whose level channel is board-side; STR/DEX/INT remain class-side.

`constitution.tres`'s `default_value` is **0**, not 10 like the other four attributes — deliberately, so a level-1 *bare* board's `node_health` baseline stays at flat 10. The +10 baseline arrives as BalancedCore's class grant (#271), matching how the other attributes get theirs.

CON does **not** get an intrinsic targeting `armor` or `min_damage_taken` — D-11 decision 3 is load-bearing (a prior draft that let CON drive `armor` produced a permanent dead zone against uninvested attackers). `test_constitution.gd` guards this explicitly.

**Procgen home (v4, #321):** `procgen/pools/constitution.tres` is CON's own `StatPack` (`archetype_stat = &"constitution"`, mirrors `strength.tres`'s ADD_BASE/INCREASE/MULTIPLY pools targeting the `constitution` stat itself — not `node_health` directly). It is a **mixed pack**: alongside the CON-primary `StatPool`s it carries **universal** pools (`archetype_stat == &""` — `node_health` INCREASE, `armor` ADD_BASE, and the `intelligence` INCREASE **debuff** `unit_value=-5, max_tier=1` whose negative cost refunds 1 budget). Universal pools are drawn by *every* node regardless of `primary_stat` — they are v4's shared defensive/mobility axis (D-12's off-archetype phase is gone; v4 deleted `off_phase_op_weights`, `Role.DEFENSIVE`, `flatten_for_phase`; see `docs/domain/procgen-v4.md`). `test_constitution_pool.gd` pins the universal pools + debuff; `test_constitution.gd` pins the board intrinsics.

**`constitution.tres` is a mixed pack** — v4's `flatten_for_node(primary_stat)` filters per `StatPool.archetype_stat`: CON-primary pools are drawn only by CON nodes, universal pools (`&""`) by every node. The pack-level `archetype_stat` is inert documentation. Moving a pool between "primary" and "universal" is *not* a no-op in v4 (it changes which nodes draw it) — author the per-pool `archetype_stat` deliberately.

**#299 also dropped `node_health` ADD_BASE entirely.** Base `node_health` is `10 + CON` and `BalancedCore` grants +10 CON at level 1, so a flat `+2–4` draw was numerically identical to the `+10–20%` INCREASE draw at level 1 and decayed from there. Only the percent channel survives, re-ranged to `+5–15%` (floor is 5% because `node_health` is INT-typed: at an L1 base of 20, a `+2%` roll is +0.4 HP and rounds away).

**HUD gap (#228, partially closed by #289):** `AttributeRules` no longer has a per-attribute `match`, so CON's hover lines (`node_health`, `health`) now render. `ui/hud/attributes_panel/attributes_panel.gd` still hardcodes the 5-attribute row/radar list, so CON has no row to hover from — that half remains open under #228.


## Local stats (per-node overrides)

**Grant routes are data on `StatDef` (#1275)** — a SkillNode's two routes only (loot and core classes write a board directly):
- **`local_grantable`** (default **false**): may a node grant it onto its own board (addon `local_modifiers`, an effect's node grant)? True iff production code folds it per node. The local door has two bodies, each gated once: `SkillNode.add_local_modifier` (live) and `NodeCombat.add_local_modifier`'s `host == null` branch (shadow — status effects and `EffectContext.grant(_at)` reach it); both `push_error` and reject anything else, and the door returns its verdict so `EffectContext` never ledgers a reject (producers never re-check). A new node-local read means flipping this flag on its def.
- **`entity_grantable`** (default **true**): may a node grant it to its owner (`modifiers`, addon `entity_modifiers`)? False iff a strip's revoke corrupts a ledger (`skill_points`, `level`, `xp`). `StatRegistry.is_entity_grantable` vetoes a parent whose descendant is non-grantable. Both entity doors reject the whole modifier.
- `StatRegistry.check_residency()` errors at load on a def neither on the entity board, nor a node pool def (`NodeStatBoard.pool_def_ids()` — `node_combat_health` / `node_spikes`, minted from, never targeted), nor `local_grantable`. `test_stat_grant_routes.gd` lints shipped content against both flags.

`SkillNode.node_board` is a `NodeStatBoard` — owned stats baked, borrowed ones created only when a node-local modifier targets them (via `_ensure_local_stat(id)`) or when the node is allocated (combat health pool). No `LocalStat` class — the merge happens directly: `StatBoard.get_stat(id)` may differ per board, and combined reads use `ModifierBins.compute()` with bins from both the entity and node board.

Read side: `SkillNode.get_local_value(id)` returns the combined value without allocating — entity stat pass-through when the node board has no stat for that id. Modifier target side: `_ensure_local_stat(id)` creates (if needed) and returns the stat on `node_board`; addons route their `local_modifiers` here.

**SET tiebreak:** highest priority wins; at equal priority **last source listed wins**. The combined read orders `[entity.bins, node.bins]` so a node-local SET beats an entity SET at the same priority.

For entity-absent fallback: `get_local_value(id)` uses `StatRegistry.get_def(id).default_value` when neither board carries the stat.

**A new `StatDef` must be added to `stats_system/stat_def_roster.tres`, not just dropped in `defs/`.** `StatRegistry` reads that authored roster and **never scans the directory** — a scan finds nothing inside an exported PCK (the exporter rewrites every `.tres` into `.res` + `.tres.remap`), which shipped a build where *every* stat lookup failed while the editor and the whole suite stayed green. That is #597 D13, "directory scan for editor and test code, authored array for runtime". `test/unit/test_stat_def_roster.gd` fails if the directory and the roster drift apart, so this is enforced, not remembered. See `docs/domain/exporting.md`.

**`StatDef.lower_is_better` (#729) is which way is "up" for a stat — `false` by default (more is better), set `true` for a stat where less is the win (`min_damage_taken`, `dealloc_damage`).** `StatDef.is_improvement(delta: float) -> bool` is the one accessor: `delta < 0.0 if lower_is_better else delta > 0.0`, `0.0` never an improvement either way. It's a **DELTA predicate only** — it can't judge an absolute value, just whether a change is better or worse — so `DeltaChip.pop(delta, decimals, suffix, def)` consumes it directly (the optional `def` colours the chip by polarity while the arrow/sign stay arithmetic truth), and `StatModifier.valence()` composes it with the op law below. `StatValueRow`, floaters and `StatModifier.format()` stay untouched; `ModSlabRow.bind` reads `valence()` and renders a BANE as a cursed slab (`SlabRow.SlabStyle.HARMFUL` — the stat hue stays on the text, the material turns to `Emissive.HARMFUL`, the same red `DeltaChip.negative_color` reads).

**The valence law (#1050): a modifier's delta is its value's DISPLACEMENT FROM ITS OP'S NEUTRAL ELEMENT.** `StatModifier.displacement_from_neutral(op, v)` is the single home of "which value is this op's no-op" — `v` for ADD_BASE / ADD_BONUS / INCREASE (neutral `0`), `v - 1` for MULTIPLY (neutral `1`), `NAN` for SET (no neutral element to measure from — callers MUST `is_nan()` first). It is static and value-taking so a procgen candidate can be judged before any `StatModifier` holds it; `GraphProcgen._is_neutral_result` routes through it rather than keeping a second copy, keeping only its own two rules (a SET is never a no-op; coerce to the stat's type first) at the call site.

`StatModifier.valence(board = null) -> Valence` composes that with `is_improvement`: **BOON / BANE / NEUTRAL / VOLATILE**. VOLATILE is the owner's fourth state for "no side to pick" — a SET (NAN displacement), a **sign-flipping MULTIPLY** (`value <= 0`, the one op that carries the held value across zero, so two of them cancel), and an unresolvable `stat_id`. Valence is **holder-relative, never viewer-relative**: an enemy's `-3% Dexterity` still reports BANE, and it never consults `ownership_bit`. It reads the same number the row next to it prints — `board` goes straight to `get_effective_value`. **Never re-derive `sign XOR lower_is_better` at a call site**, and never `log(v)` for MULTIPLY (rejected: `log(-1.0)` is a silent NaN that fails both comparisons, quietly rendering a `×-0.4` as a bane). `StatPool._get_configuration_warnings()` flags a MULTIPLY pool whose folded `1 + magnitude` range reaches `<= 0`, since nothing authors a sign-flipper on purpose today.

**A stat is volatile on a read iff a modifier THAT READ FOLDS has `valence(board) == VOLATILE` (#1238)** — `Stat.is_volatile()` (its own bound modifiers, judged on its own `_board`, so a formula MULTIPLY crossing zero at runtime counts), `StatBoard.is_stat_volatile(id)` (entity readout; never mints), `NodeCombat.is_local_volatile(id)` / `SkillNode.is_local_volatile(id)` (node board OR owner's entity board — the two sources `get_local_value_with` folds). No special cases, no cache.

### Node regen stats (`node_healing` / `node_healing_ramp`, D-9 #270)

Two **node-local** scalars read through `get_local_value` — so a single node can be tuned to regen faster than its owner's baseline. `node_healing` is the flat per-turn heal; `node_healing_ramp` is the extra granted per consecutive undamaged turn.

The stack counter itself is **runtime state on `SkillNode` (`regen_stacks`), not a stat** — same reasoning as node HP: it's per-node combat bookkeeping that resets constantly and nothing should be able to modify it. **There is deliberately no cap stat**; the ramp self-limits by stopping at max HP and resetting. Don't add one.

**Shots are runtime state too, not a stat (#956).** `max_shots_per_leaf` is the entity-board scalar (default 5, read node-locally: × `stake_level__current` intrinsic, + Watchtower `local_modifiers`), but what a leaf has *fired* this turn lives in `SkillNode.shots_fired_this_turn` and `shots_left()` is the subtraction — never a node-board pool, never a modifier. **Why:** it must survive a same-turn dealloc → re-allocate (allocation refills node pools — `SkillNode.refill()`, spikes-to-full — so a pool would read full again; nothing on the allocation path touches a runtime field) and must reset at the *firer's* turn end even if the node changed hands. **How to apply:** bump it only via `mark_shot_fired(n)` from the command commit path and append the node to `Entity._fired_nodes_this_turn` in the same breath — `finish_turn` resets exactly that set (the `_spiked_nodes_spent` discipline, never a sweep). `volleys_launched_this_turn` on the Entity is the same shape against board `volleys_per_turn`, reset at turn start.

Turn-start refill-to-full is **gone** (D-9) — damage persists across turns. `SkillNode.refill()` survives for the allocation path only, and the resulting dealloc/realloc full-heal is an **accepted interaction, not a bug** (it costs DP/MP and needs topology permitting the dealloc without islanding). See `docs/domain/node-hp.md`.

### CoreClass auras (D-10, #270; ported onto `AuraEffect` in #720; CON scaling in #896)

A class's turn-start healing aura is `HealAuraEffect` (`effects/heal_aura_effect.gd`), an `AuraEffect` subclass authored on `CoreClass.effects` like any other class effect (Ninja/Serpent) — there is no separate `CoreClass.aura` field or standalone `CoreAura`/`HealAura` pair anymore. The falloff is whatever `reach`/`metric`/`distance_scale` the resource carries: Balanced pairs `HopRangeFinder(max_hops 4)` with `ExpressionScale("v - d")` for an absolute ladder over hops 0–4, `v` scaled with CON below (#900's scale-returns-the-value shape, not a derived range).

- **`base` and `con_coefficient` live on the effect resource, NOT the stat board.** Don't add `aura_heal_base`/`aura_heal_range` as stats.
- **Sub-linear CON scaling (#896, D-10): `v = base + con_coefficient × sqrt(CON)`** is what's handed to `distance_scale.scale(d, bound, v)` — CON read LIVE off `ctx.entity.stat_board.get_value(&"constitution")` every `_on_turn_start`, never cached on the resource (a board stat read as a formula input, see this file's own stat-formula-input rule). `sqrt` is deliberate: `node_health` grows ~linearly with CON, so a flat aura decays into irrelevance as levels climb, but matching that growth 1:1 would keep the fortress dominant forever. **`max_hops` never scales** — the level channel is the payload only, coverage stays ~quadratic in radius regardless of CON.
- **Hop distance is measured over the OWNED subgraph** (`entity.navigator`, reached through `EffectContext.navigator`) via `RangeFinder.gather`, never the global navigator and never `in_range` in a loop — see `.claude/rules/graph.md`.
- **A payload-channel subclass, not a membership one** (see `docs/domain/effect-system.md`'s payload seam): the heal is a per-turn amount, so `HealAuraEffect` overrides `_on_turn_start(ctx)` rather than `_grant_to` — `_grant_to` is a deliberate no-op, and `_has_payload()` reads `base > 0.0 or con_coefficient > 0.0 or distance_scale != null` since this channel carries no `modifiers`.
- The aura heals **through** the damage gate but **grants no ramp**; it's additive outside the ramp term: `total = (node_healing + stacks × ramp) + aura_at_hop`.
- **Clamped at 0 regardless of `discard`.** A negative computed value would be damage with no `AttackRecord` behind it (`.claude/rules/attack-timeline.md`), so `_on_turn_start` does an explicit `maxf(computed, 0.0)` before healing rather than relying on the `discard` policy, which only ever decided whether a MODIFIER-channel value was worth granting.
- `AuraEffect` itself is a **channel, not a payload** — armor/damage auras are equally valid alongside heal ones. Don't hardcode "aura == healing" into its shape.

### Node combat health

The node's health is a `PoolStat` on `node_board` with **id `node_health`** — the same id as the entity board's ScalarStat baseline, a different `Stat` class — minted off the **`node_combat_health` def** (`StandardPoolStatDef`, FOLLOW on *both* cap axes). The id and the def are not the same string; this line said `node_combat_health` was the id until #702. `deplete()` / `restore_to_full()` replace the old `current_hp` float. The def is INT and `current` stays float storage written only whole: each of the four HP doors (`NodeCombat.take_damage`/`heal_damage`, `EntityCombat.take_pool_damage`/`heal`) floors its magnitude once via `HitPoints.land` (ADR 0017) — never floor in `Mitigation` or a formula.

**Nothing pushes the cap per node (#660).** The `base_value` sync from the owner and the `value_changed` subscription re-pushing it as CON moved are both deleted: `NodeCombat._hp_pool` installs a **`PoolStat.base_provider`** reading the owner's baseline, so the cap is derived on read, and FOLLOW-on-both makes the pool `stores_missing()` — it keeps damage taken, not an absolute fill. `SkillNode._refresh_hp_binding` is the ownership transition alone now. Consequences (a cap that moves with no notification, path independence, the sliver): `docs/domain/stat-knobs-and-bins.md` § "The policy also chooses the stored representation".

## Turn-start upkeep

`Entity.begin_turn` runs at the owning entity's turn start. It does, in order: **pool replenishment** (one declarative sweep), **wound healing** (bespoke), **node HP refill**, then the **class hook**.

### Pool replenishment is declarative (`per_turn_mode`)

"Per turn" is **three different verbs**, not one — don't conflate them:

| Verb | `PerTurnMode` | Operation | Pools |
|---|---|---|---|
| Reset-to-cap | `REFILL` | `restore_to_full()` | `action_points`, `deallocation_points`, `movement_points`, `tempo` |
| Top-up by a rate | `ADD` | `current += <rate stat>.value` (clamped) | `xp` (+`xp_per_turn`) |
| Top-up through the host's heal door | `HOST_ADD` | the pool does nothing; `Entity._apply_turn_upkeep` reads `PoolStat.host_upkeep_amount` and calls `EntityCombat.heal(amount, rate_id)` | `health` (+`core_healing`, #997) |
| Bespoke | `CUSTOM` | `PoolStat._custom_turn_upkeep(board)` override | `skill_points` (heals `wound_heal_per_turn` wounds) |

`PoolStatDef.per_turn_mode` (base-class field, default `NONE`) declares the verb. `StatBoard.apply_per_turn_upkeep()` enumerates every `PoolStat` field by introspection (`get_pool_stats()`) and calls `pool.run_turn_upkeep(self)`; the per-pool behaviour lives on `PoolStat`, the board is just the sweep. So **a new pool opts into upkeep by setting `per_turn_mode` on its def, not by editing `begin_turn`** (that was the footgun: `movement_points` was never restored and a regen-rate stat was never consumed because nobody remembered to wire them). ADD resolves its rate stat through `PoolStatDef.resolved_per_turn_stat_id()` and `push_warning`s if it's missing.

**ADD's rate stat is `<id>_per_turn` by convention, overridable by name (#277).** `per_turn_stat_id` on `PoolStatDef` (empty = the convention) exists because `health`'s rate is **`core_healing`**, named for the mechanic rather than for the pool it fills — D-25 names it, and #268 registers a balance invariant using that name, so renaming it to `health_per_turn` to fit the convention would break the traceability the design is written against. Set the override only for that reason; a rate stat with no independent identity should keep the convention. A `CoreClass.on_turn_started` hook is *not* the place for this — pool upkeep stays declarative (see the footgun above). **Every heal enters through one door per host (#997, owner: "All heals must consult it"):** `NodeCombat.heal_damage` for `node_health`, `EntityCombat.heal` for `health` — each multiplies by `healing_received` once, `raw := true` is the only bypass, and `test/unit/test_heal_door_drift.gd` scans the tree for a `replenish`/`set_current`/`.current +=` on either pool outside the two door bodies. That is why `health` is `HOST_ADD` rather than `ADD`: the def still names the rate and the route, but the pool hands the amount to the host instead of replenishing itself, so an entity-hosted Wither inverts the core's own trickle exactly as it inverts node heals.

**`CUSTOM` and the def-vs-stat hook split:** `wound_heal` isn't a pool top-up — it transfers SP from the `wounded` reservation back to `current` (a bin move inside `SkillPointStat`, conditional on `wounded > 0`). It can't be REFILL/ADD, so `skill_points` is `CUSTOM` and `SkillPointStat._custom_turn_upkeep()` does the `heal()`. Note this hook lives on the **stat** (`PoolStat`/`SkillPointStat`), whereas `on_pool_filled` / `on_max_increased` live on the **def** (`PoolStatDef` subclasses): cap-shape behaviour varies by def archetype → on the def; behaviour that touches the stat's *own extra state* (the SP bins) → on the stat. **Behaviour lives where its data lives.** A stray `REFILL`/`ADD` on `skill_points` would corrupt the `wounded`/`staked` bins — `test_per_turn_upkeep` guards the CUSTOM path.

`wound_heal_per_turn` defaults to 1. Tuning lever: raise to recover faster from forced deallocs; drop to make wound damage stickier.

**Fractional rates accumulate, they don't truncate.** `SkillPointStat.wound_heal_progress` (0..1, runtime-only) banks `wound_heal_per_turn` every turn upkeep; once it crosses 1.0 *and* `wounded > 0` it heals 1 SP and drains by 1.0. A rate below 1 (e.g. 0.5 — two turns per healed SP) would silently heal nothing forever under a naive `int(rate)` per-turn call, which is what this replaced. While `wounded == 0` the progress holds at a capped 1.0 instead of wrapping — nothing to spend it on yet — so it reads "full" until the entity is wounded again, at which point the *very next* turn upkeep immediately heals and drains it. `wound_heal_progress_changed(progress)` is what `turn_resources_panel.gd` binds its sliver to; the label showing the rate itself is always visible (not gated on `wounded > 0`) since the rate is a stat a player wants to see even unwounded.

`health` is `HOST_ADD` with `core_healing` as its rate (D-25, #277; the door since #997): an **integer** heal, placeholder `1`/turn, **ungated and unramped**. No damage gate — a gate only exists to make a ramp meaningful, and a ramping out-of-combat heal would reward exactly the camping D-10's forced-dealloc cascade is engineered to punish. (Node regen *does* ramp and *is* gated — D-9 — because a held node recovering is territory you are defending. Don't unify the two.) Integer rather than a sub-1 sliver because the gauges already render an "incoming next turn" band: `hero_sigil_card.gd` binds `health` ← `core_healing` (the same way `xp_track.gd` binds `xp` ← `xp_per_turn` since XP moved out of the card in #320), so the UI cost was zero. `test_core_healing.gd` pins the no-gate and no-ramp contracts.

**#268 invariant, named not implemented:** if `core_healing >= dealloc_damage × nodes_lost_per_turn`, camping is viable again and D-10's structural guarantee is silently undone. `1` is the break-even against a 1-node-per-turn chip — a placeholder per D-13, not a blessed value.

`initiative` is the remaining `NONE` pool (tick-driven by TurnManager, not the sweep).

### Turn-*end*: unused-AP → DP/MP surplus (#152)

`Entity.finish_turn` transfers each unused action point into next turn's `deallocation_points`/`movement_points` **surplus**, scaled by the **`ap_transfer_rate`** ScalarStat (default 2 — see "Turn Budget" board field). `boost = roundi(unused_ap × rate)`; the product is rounded so a future fractional/DEX-scaled rate doesn't truncate. Because `ap_transfer_rate` is an ordinary board stat, **class identity tunes it with no bespoke mechanism** — a Pacifist raises it, a Berserker drops it to 0 (see `PacifistCore`). `Entity.DEFAULT_AP_TRANSFER_RATE` is the fallback only for sparse/test boards that carry no such stat. This lives at turn *end*, not start, because unused AP is only known then; turn-start REFILL then leaves the surplus untouched (it's outside the cap). `set_surplus` **overwrites**, so a turn ending with all AP spent writes 0 and self-clears the prior boost. See the `SurplusPoolStat` note under "Pool stats".

### Then: node refill + class hook

- (for each node owned by the entity) `SkillNode.refill()` — node combat HP back to max.
- `core_class.on_turn_started(self)` — the wired class runs its own per-turn effects (caster flourishes, rage decay, etc.). Default hook is a no-op.


## Effect-granted modifiers (#4)

`Effect`s grant modifiers through `EffectContext.grant(mod, target)`, which
`.duplicate(true)`s once and records the handle in the `EffectInstance` ledger.
`target` is null (entity board) or a `SkillNode` (its `node_board`).

**Provenance is the retained handle, not a field.** `StatModifier` still has no
`source`, and `ModifierBinding.Kind` stays dormant — the ledger makes `revoke_all`
exact without changing the schema. Don't add a source field for this.

**Never store runtime state on an `Effect`** — a single `.tres` is shared across
every entity carrying it. State goes on the per-grant `EffectInstance`.

Entity-scoped node modifiers now route through `SkillNode.add_entity_modifier` /
`apply_entity_modifiers_to(board)` rather than callers hand-rolling
`modifiers.append(m)` + `board.add_modifier(m)`. Node-scoped ones go through
`add_local_modifier` / `remove_local_modifier`. See `docs/domain/effect-system.md`.

### `grant_at` writes the duplicate's LEAVES, before granting (#623, #900)

`EffectContext.grant_at(mod, values, target)` — the aura distance path — must
never write the modifier it hands to `grant`/`add_local_modifier`
*after* the fact. `StatBoard.add_modifier` and `SkillNode.add_local_modifier`
both flatten a `CompositeStatModifier` into its children and bind each **leaf**
directly; the outer composite's own `value` field is vestigial from that point
on, so a post-bind write to it is silently lost. The same shape bites a
**plain** formula-bearing modifier on a clone/shadow board too:
`StatBoard._localize` (`stat_board.gd:401-408`) hands the binder a *private
copy* the moment `_is_clone` and `m.formula != null`, so a post-bind mutation
of the original object never reaches what got bound.

The fix (and the only correct shape): duplicate, walk `duplicate.flatten()`,
SET each **leaf's** `.value` from `values[i]`, THEN apply the already-valued
duplicate through the ordinary `grant`/`add_local_modifier` path. Composites,
shadow boards, and formula-bearing modifiers all fall out of this for free —
there is nothing downstream left to get wrong. Never reintroduce a
write-after-bind to `grant_at`.

**#900 renamed it from `grant_scaled` and changed what it takes**: one
already-computed value per leaf (`PackedFloat32Array`, in `flatten()` order),
not a single multiplier. `DistanceScale.scale(d, max, v)` now returns the value
itself, so there is nothing left here to multiply — and a composite's leaves
each get their own result, which a single float could not express. It stays one
array rather than a per-leaf call because a composite is granted as **one**
handle: `_apply` ledgers it once and `add_modifier` does its own flattening.

### The local-scale ladder (#376) is reapplied at INSERT (#634)

The ladder itself is **linear — `1 : 2 : 3`** — for every scaling modifier
alike, and MULTIPLY scales its *growth part* (`1 + (X−1)·ladder`), not its whole
value. Settled, re-affirmed, and not to be re-argued without evidence from play:
**[ADR 0004](../../docs/adr/0004-the-allocation-level-magnitude-ladder-is-linear.md)**.
The law lives in `skill_node/local_scale_mutator.gd` (`LocalScaleMutator`, a stateless verb over a `NodeState`); `SkillNode` keeps only the `stake_level.current_changed` trigger, and the swap ledgers live on `NodeState`.

A modifier lands on `add_local_modifier` at its AUTHORED (baseline, al=1)
value — an aura re-grant included, since #623's fix scales the aura's
*distance*, never the node's allocation ladder, and those are different
owners that must not merge. `SkillNode.add_local_modifier` therefore ends by
calling `LocalScaleMutator.scale_modifier(state, m, 1, _last_allocation_level)` — the same
universal-law / `_local_scale_override` walk `apply` runs per
stake change — bringing the freshly bound handle up to the node's *current*
allocation level immediately, rather than leaving it at baseline until the
next `stake_level` change happens to fire `_on_stake_level_changed`.

**Why this doesn't double-scale:** `_local_scale`'s ladder is floored at 1, so
`al ∈ {0, 1}` both read as baseline — a fresh grant is always "coming from
al=1" regardless of `_last_allocation_level`'s literal value at grant time.
`LocalScaleMutator.apply`'s later per-stake-change call then applies its OWN delta
from wherever the handle now sits, which composes correctly (grant at al=3,
stake to 4: `x 4/3`) — see `test_grant_at_al3_then_stake_round_trip_returns_exactly_no_double_scaling`.

**Ownership stays with `SkillNode`, not `AuraEffect`.** The rejected
alternative — an aura pre-scaling by `allocation_level` before granting —
would leave the *next* `LocalScaleMutator.apply` walk applying its delta AGAIN on
top (double-scaling), and would split the ladder's authority across two
systems. Scaling at insert needs no new state (bind and scale are one act) and
covers every `add_local_modifier` caller — addons included, not just auras.


## Dependency-cycle rejection (#322)

The formula dependency graph (`stat_id -> formula.get_input_ids()`, i.e. "this stat
depends on that one") must stay a DAG — `StatModifier._propagating` only guards
re-entrancy on one modifier's `_on_source_changed`, so a genuine A→B→A cycle doesn't
error or hang, it just settles on a **silently wrong, evaluation-order-dependent**
value. `test/unit/test_stat_dependency_graph.gd` statically checks the shipped
content (board intrinsics + each core class layered on top) is acyclic; it cannot
cover a modifier added at **runtime** (a looted formula modifier rebinding to the
looter's board, where its source may already derive from its own target).

`StatBoard.cycle_from(m)` is the runtime half (`would_cycle(m)` is its bool
wrapper): it folds the candidate's edges into a graph, folds everything already
**applied** on top, and runs a DFS. `StatBoard.add_modifier` calls it as a
precondition and rejects (`push_warning`, no-op) rather than accept-and-corrupt —
checked *before* any leaf is bound, so a rejection leaves the board provably
unchanged. **The warning reports the offending path, never `m.stat_id`** — a
`CompositeStatModifier`'s `stat_id` is vestigial/empty, and a bundle is the case
most worth diagnosing.

**The search is rooted at the candidate's own target stats, not at every vertex.**
Edges run `stat_id -> input`, so any cycle containing a newly added edge is
reachable from that edge's tail — rooting there is sufficient *and* strictly
narrower. That's correctness, not just speed: a whole-graph search reports a cycle
the candidate had no part in and rejects an innocent modifier for it. It also
means a candidate with no edges (static, or a formula with no declared inputs)
yields no roots and the live graph is never folded at all — the short-circuit
falls out of the shape instead of being a special case.

**Edges are collected in place, never as a modifier list.**
`StatModifier.collect_formula_edges(out)` is the single definition of what an edge
is; `CompositeStatModifier` overrides it to recurse (same seam as `flatten()`,
without the per-leaf array). `Stat.collect_formula_edges(out)` folds its own
`_modifiers` — tell-don't-ask, so `_modifiers` never leaves the `Stat`. There is
deliberately **no `Stat.get_modifiers()`**: handing that array out lets a caller
append an unbound modifier that sits in the list without contributing to `bins`
(silently wrong values, no error), and a per-stat copy on a path that wants a
handful of edges is pure churn.

**Live vs. authored are two different reads, on purpose.** `StatBoard.collect_formula_edges`
reads what is **applied** (`Stat._modifiers` across every field, hardcoded + `_extra_stats`);
`StatBoard.adjacency_from(mods)` is `static` and reads an **authored** array — the
board's `intrinsic_modifiers` and a `CoreClass.modifiers` are inert until
`apply_intrinsics()` / `apply()` attach them. The static test needs the authored
read because it must fire *before* anything is applied. Don't unify them.
`StatBoard.find_cycle(adjacency, roots := [])` is shared by both (empty `roots`
= whole graph, which is what the static check wants). Don't re-derive this DFS a
third time.

**Runtime rejection has no notion of who *should* win — the static check is what
makes that safe.** Whichever side arrives second is the one rejected. `Entity._ready`
runs `stat_board.apply_intrinsics()` **then** `core_class.apply(self)`
(`entity/entity.gd:122-124`), so today a shipped conflict would drop the *class*
modifier and keep the board intrinsic. Flip that order and a cycle silently voids a
board intrinsic instead. Don't reorder it, and don't treat `would_cycle` as
sufficient on its own: `test_every_authored_core_class_is_acyclic_on_top_of_the_board`
is what stops shipped content from ever reaching the runtime gate. It discovers
classes via **`CoreClass.load_all()`** (scans `CoreClass.DIR`), so authoring a new
class enrols it automatically — the old hand-maintained preload list could go stale
in silence. It carries a `MIN_CORE_CLASSES` vacuity floor because a directory scan
that matches nothing passes every assertion below it.

**Scope note (#340):** `SkillNode.add_local_modifier` does NOT route through
`StatBoard.add_modifier` — `get_stat` would silently drop a sparse-board target —
but it mirrors that method's cycle-check → bind → resolve-target sequence locally
against `node_board` (`cycle_from` gates it, `bind_modifier` binds each leaf). So
node-local formulas do compute, and gate and binding ship together.

