# Stat knobs and pool bins

Two authoring questions that keep getting re-derived from scratch, answered once.

- **"This rule needs a tweakable rate. Where does the knob live?"** → §1 (a
  modifier's `value`, until something targets the rate — then a stat)
- **"This pool needs a second bucket alongside `current`. How do I add one?"** → §2
- **"Why did writing `base_value` not trigger the ratchet?"** → §3
- **"How do I force a stat to exactly N?"** → §3 (`base_value` only if the base
  *is* the number; a derived stat wants a `SET` modifier)
- **"This rule steps up at 10 / 100 / 1000. Can I just use a log?"** → §4 (no)
- **"A spell/relic/aura authors its own number and the stat should modify
  *that*. Whose base is it?"** → §5 (an overlay bin when a flat in the stat's
  unit is meaningless; a rate stat keeps base 1 and multiplies it)

`.claude/rules/stats-system.md` is the *reference* — what exists, and how the
pipeline computes. This doc is the *decision procedure* for adding something new.

---

## 1. A stat is a target; a rate nothing targets is a modifier's `value`

**Decision (owner, 2026-09-21, #1016).** Supersedes #298's preliminary "add a
board scalar per coefficient and leave `StatModifier.value` at 1.0".

- **A stat is a target.** Something *else* — a procgen roll, a loot drop, a node
  addon, a status, a readout row, the wire — wants to land a modifier on it or
  read it by id. That is what a def + board field + `.tres` instance + registry
  entry buy, and it is the only thing they buy.
- **A rate nothing targets is a modifier's `value`**, authored on that
  modifier's `.tres` (inspector-tunable) and mutated — if ever — through the live
  modifier, riding the existing recompute + `value_changed` chain. It earns a
  stat the day something targets it, not before.
- **No migration of existing knobs.** `core_health_scaling` and
  `node_health_scaling` stay stats: sunk cost, harmless, and
  `node_health_scaling` is the named plausible future roll target (a `+0.1`
  `ADD_BASE` on it is a valid procgen affix — nothing rolls it yet). They are
  the worked example of "becomes a stat when a roll wants it", already there.
  The criterion governs new knobs and any existing one touched for another
  reason.

Owner's framing, verbatim: *"some stats are actually just 1 modifier to 1 bin of
another stat, which makes me question if that former stat should exist
altogether … it might as well have been a var with a getter+setter to update a
live (already applied) modifier and letting it ride the signal + recalc
pipeline instead of authoring an entirely new stat just for basically 1
multiplicative modifier in another stat."* An added stat is light, but every
one taxes stat lookup and authoring DX; a stat per innate rate, plus an innate
modifier that reads that stat back, is the shape to refuse.

### Authoring a rate as a modifier value

```
health      = 10 + 1.0 x CON      # intrinsic ADD_BASE, formula = CON, value = 1.0
node_health = 10 + 1.5 x CON      # same shape, value = 1.5 — the rate IS the value
```

One `StatModifier` sub-resource on the board `.tres`: `operation`, `formula`
(the input it scales), `value` = the rate. `get_effective_value` is
`value × formula.compute(board)` (`stats_system/stat_modifier.gd`), so the
coefficient needs no stat of its own to be read reactively: the formula
subscribes to its inputs, and the `value` setter recomputes and emits
`value_changed` on its own (#893). Both channels land in the target's bins.

### Tweaking the rate live — an applier holding its modifier is the shape

An object that applied a modifier (an `Entity`, a status, a class) may hold the
ref and write `value` to move the rate at runtime — that is the intended door,
not a smell: the applier owns the contribution, the stat owns the fold, and the
`value` setter is the named entry between them. Three constraints ride with it:

1. **Hold the ref from apply time**; never re-find "my" modifier by scanning the
   stat's list. Today `add_modifier` returns `void` and localizes formula-bearing
   modifiers on clone boards, so a held ref can be the dead original — #1034
   makes the door return the live leaves.
2. **Only ever tweak the entity's own copy**, never a modifier still shared from
   a board `.tres` (the `localize_formula_modifiers` hazard).
3. **A tweak on the authority reaches peers** through a confirmed command or the
   next `to_dict` sync — never a host-only `_process` write.

### Two rates that read alike and are not the same number

Both shapes are expressible — a formula-bearing modifier honours its
`operation`, so a `MULTIPLY` whose formula reads CON is as legal as an
`ADD_BASE` whose formula does. They diverge the moment the rate is not 1:

```
coefficient inside the ADD_BASE formula : 10 + 1.5 x CON    # a rate on ONE INPUT; the flat 10 stays a floor
MULTIPLY bin on the target              : (10 + CON) x 1.5  # a rate on the TOTAL; scales the 10 and any INCREASE too
```

Pick by what the rate should scale, not by what the plumbing allows — it allows
both. D-21/D-26 chose the coefficient form for `health` on purpose so the flat
base stays fixed while only the attribute channel scales; match it unless you
mean the other thing.

### When a rate does become a stat: the three files

The day a roll, a relic or a readout targets the rate, promote it — the
promotion is additive, nothing migrates:

1. `stats_system/defs/<knob>.tres` — a `StatDef`, `value_type = 1` (FLOAT),
   `default_value = 1.0`, with a `modifier_name` that reads well in a tooltip
   ("Health per CON"). Copy `core_health_scaling.tres`.
2. `stats_system/stat_board.gd` — one `@export var <knob>: ScalarStat` in the
   matching group. **The field name must equal the stat id** (`get_stat` is
   `Object.get(id)`).
3. `entity/default_entity_board.tres` — the `ScalarStat` instance
   (`base_value = 1.0`), and an `ExpressionFormula` on the consuming intrinsic
   listing **both** ids in `inputs` (`"node_health_scaling * constitution"`), the
   modifier's `value` back at `1.0`. Miss the knob's id in `inputs` and moving
   the knob won't rebind — the modifier subscribes to exactly what `inputs`
   declares.

What the promotion buys, and only then earns: a lootable "+30% node HP per CON"
through the one modifier pipeline, `AttributeRules` hover discovery via
`scales_with(attr_id)`, the inspector and the stat-board visualizer
(`addons/stat_board_visualizer/stat_board_graph.gd` — `_GROUP_LAYOUT` is a
hardcoded id list; add the knob there if you want it drawn). The board is a flat
namespace mixing what an entity *has* (`strength`) and coefficients of a *rule*
(`core_health_scaling`); `StatDef` has no `category` / `hidden` marker (retired
in #120). That is why a rate waits for a targeter — the namespace tax is paid
per stat, and a marker field is a pure addition if the knobs ever multiply.

### When a rate IS a stat: not every one is a formula input

Not every targetable rate is a coefficient. Existing board scalars are read
three ways — pick the one that matches:

| Shape | How it's read | Examples |
|---|---|---|
| **Formula input** | in an `ExpressionFormula`'s `inputs`, recomputes reactively | `core_health_scaling`, `node_health_scaling` |
| **Imperative** | plain GDScript read at the point of use | `ap_transfer_rate`, `dealloc_damage`, `crit_multiplier`, `initiative_speed` |
| **Pool rate pointer** | named on a `PoolStatDef` via `per_turn_stat_id`, consumed by `run_turn_upkeep` | `core_healing`, `mana_per_turn`, `wound_heal_per_turn` |

All three are board stats because something targets them (a class, a relic, a
readout), so all three stay class-tunable. Only reach for a formula input when
the value genuinely participates in computing another stat.

---

## 2. Pool bins — the buckets that wrap `.current`

A `PoolStat` is a cap (`.value`, from the modifier pipeline) plus one ephemeral
`current`. A **bin** is an extra named bucket alongside `current`, for state that
is neither "the cap" nor "spendable right now".

Two shipped examples, and they sit on opposite sides of the cap:

| Bin | Class | Position | Meaning |
|---|---|---|---|
| `wounded` | `SkillPointStat` | **inside** max | SP knocked out by attack, recoverable via `heal()` |
| `staked` | `SkillPointStat` | **inside** max | SP committed to node cap raises, recoverable via `extract()` |
| `surplus` | `SurplusPoolStat` | **outside** the cap | one-turn budget boost; `available()` may exceed `.value` |

### The shape

```gdscript
signal wounded_changed
signal wounds_applied(amount: int)     # delta signal, for animation triggers

@export var wounded: int = 0:
    set(v):
        var clamped: int = max(0, v)
        if wounded == clamped:
            return
        wounded = clamped
        wounded_changed.emit()
        value_changed.emit()
```

Four rules, each of which has already cost something:

1. **A bin is an `@export var` with a clamping setter** that emits its own
   snapshot signal *and* `value_changed`. Two signals because UI wants both: a
   snapshot re-render, and a delta to animate ("you lost 3 SP"). A getter alone
   won't do — the clamp is the invariant.
2. **Transfers are named methods, never arithmetic at the call site.**
   `spend`/`refund`/`wound`/`heal`/`stake`/`extract` each conserve the bucket
   identity (`used == max - current - wounded - staked`). A caller doing
   `sp.wounded += 1` by hand skips the conservation and silently desyncs `used`.
3. **Decide inside-max vs outside-cap first — it changes everything downstream.**
   Inside, the pipeline clamps the bin for you. Outside, you must actively make
   the pipeline *ignore* it: `restore_to_full()` only moves `current`, the
   modifier pipeline never consults `surplus`, and a `SET cap = 0` pool with
   nonzero surplus has to stay a legal state.
4. **A derived total must be an untyped property or a plain method.** This is the
   trap:

   ```gdscript
   var used:                                   # untyped — runtime only
       get: return int(get_value()) - roundi(current) - wounded - staked

   func available() -> int:                    # or just a method
       return roundi(current) + surplus
   ```

   A *typed* computed property (`var used: int: get: ...`) gets persisted by the
   editor's resource serializer as `used = null` in the `.tres`. Untyped
   computed properties — matching `Stat.value`'s shape — stay runtime-only. Both
   `SkillPointStat.used` and `SurplusPoolStat.available()` carry this warning in
   their own docstrings; heed it in the third one too.

### Where the behaviour goes: stat or def?

**Behaviour lives where its data lives.**

- Cap-*shape* behaviour varies by pool archetype → put it on the **def**
  (`PoolStatDef.on_pool_filled` / `on_max_increased`).
- Behaviour touching the stat's own extra bins → put it on the **stat**
  (`PoolStat._custom_turn_upkeep`, which is why `skill_points` is `CUSTOM`:
  wound-healing is a bin transfer, not a top-up, so REFILL/ADD cannot express
  it — and a stray REFILL on `skill_points` would corrupt the bins).

---

## 3. One `base_value` door, and the policy is authored data

**Decision 2026-08-24 (#555), extended 2026-08-29 (#660).** There is exactly one
door onto a pool's cap — `pool.base_value = v` — and the def decides what happens
to `current` when it moves. Owner, verbatim on the old second door:

> *"`set_base_ratcheted` in my view has never had a right to exist, was pure
> smell. because ratcheting behavior (follow on rise) imo is a knob we should set
> on the pool, which changes the behavior of the setter (setters can be
> overridden in subclasses too if needed)"*

`Stat` declares `base_value` with `set = _set_base_value` **precisely so
`PoolStat` can override it** — the `set = _method` property form is
subclass-overridable, the inline `set(v):` form is not. So a plain assignment,
even through a `Stat`-typed reference, runs the def's policy. That is what makes
the ordinary-looking write the *correct* one.

### The policy is two authored enums on `PoolStatDef`

| Knob | Values | Meaning |
|---|---|---|
| `on_cap_rise` | `PIN` / `FOLLOW` | cap up: `current` sits still, or rises by the same delta (the D-21 ratchet) |
| `on_cap_fall` | `CLAMP` / `FOLLOW` | cap down: `current` moves only if it would exceed the new cap, or drops by the same delta |

**The clamp is an invariant, not a mode.** `current` is bounded by the cap after
either policy runs, and no mode switches that off. Budget that legitimately
exceeds the cap is a *separate bin* (`SurplusPoolStat.surplus`), which the
cap-change policy never touches.

### The mint door is private, and there are four sites

`PoolStat._set_base_minted(v)` moves the base *without* the policy. It is private
and lives entirely inside `stats_system/`: `SkillPointStat.claim`,
`SkillPointStat.grant`, `GrowablePoolStatDef.on_pool_filled`'s growth, and
`PoolStat._read_base` (a wire snapshot transports a cap; that is not a cap
*change*). Board init and `StatBoard.clone_live` use it for the same reason.
**A mint is "this pool's own base is game state it grows itself"** — never "the
cap followed something else", which is a plain assignment.

### The policy also chooses the STORED REPRESENTATION (#660)

`PoolStat.stores_missing()` is derived from those same two enums, not from a
third switch:

- `FOLLOW` **on both** rise and fall → the pool stores **damage taken**, and
  `current` is *derived* as `max(floor, cap − missing)` on every read.
- anything else → the pool stores an absolute `current`, as it always did.

One accessor either way: `current` is always read and written in absolute units,
and nothing outside `PoolStat` knows which representation it is holding (house
rule: no parallel mirrors of logic). What falls out of missing-storage rather
than being implemented:

- **the cap can move with no notification at all** — which is what let #660
  delete the CON→`node_health` fan-out, where every owned node held a
  `value_changed` subscription and re-pushed its own cap on every CON swing;
- **path independence** — a cap that dips and returns leaves `current` exactly
  where it was. The old `FOLLOW` rise + `CLAMP` fall pair forgave damage down to
  the dip and handed it back on the way up, so a dealloc/realloc CON round trip
  *healed* you. Nobody designed that, and it is gone;
- **the sliver** — a fall past the damage floors at `min_value` instead of
  killing. Death stays exclusively inside `NodeCombat.take_damage`, so a node
  driven to the floor by pure stat loss survives and dies to the next real hit.

`node_combat_health` is the only def on this side today. Entity-board pools
(`health`, `mana`, `action_points`, …) have a fan-out of 1 and stay
stored-current.

**How this bit us (#346).** Back when the raw write was the *silent-bypass* door,
`SkillNode._sync_combat_health_base()` used it to follow the owner's `node_health`
baseline. Every allocated node's cap rose with CON while `current` stayed frozen,
and node regen (~1/turn) could not close a widening gap — nodes drifted toward
reading near-empty. #555 inverted the default so the ordinary write is the safe
one; #660 deleted the sync entirely.

**How to apply:** move a cap with `pool.base_value = v` and author the policy on
the def. If you find yourself wanting `_set_base_minted`, you need a reason you
can name in a comment, as `claim()` does — and you need to be inside
`stats_system/`.

### The door is onto a POOL's cap — a DERIVED baseline wants a SET modifier

Found 2026-09-01 wiring the spell playground's node-HP slider (`9b1287f`).

The rule above is about a pool whose base *is* the number. It does not transfer
to a stat that §1 made **derived** — `node_health` on the entity board is
`10 + node_health_scaling × CON`, and `base_value` is only the `10`. Writing it
moves the result by the same delta but never *to* the value you wrote, so a
control labelled "node HP = 50" caps nodes at 50 + CON. Silent: nothing is out
of range, the number is just not the one you asked for.

`StatModifier.Operation.SET` is the one that means what the caller said — it
bypasses the pipeline, intrinsic included, so the modifier's `value` **is** the
stat's value. Add it once through `board.add_modifier(m)`, keep the reference,
and drive it by assigning `m.value`: the setter emits `Resource.changed`, which
every `Stat` holding the modifier already subscribes to
(`stats_system/stat.gd:370`), so the recompute and the whole `value_changed`
fan-out follow from the assignment. There is no re-add and no board poke, and a
`SET` that arrives after yours simply wins on `priority` — which is the right
outcome for a debug override.

**How to apply:** ask what the stat's value is *made of* before reaching for
`base_value`. Base is one input among several → SET a modifier. Base is the
whole number (a pool cap, an unmodified scalar) → the one door above. What you
must not do is the third option: back-solve the base by subtracting the
intrinsic's contribution in the caller, which is a second copy of the formula
and dies the first time the formula changes.

**Where this pays off beyond debug knobs.** A SET is composable in a way a base
write is not — it is removable (drop the modifier, the derivation comes back
untouched), it is stacking-aware, and it survives everything that legitimately
rewrites a base underneath it. That makes it the shape for a curse, an aura, or
a "all nodes are 1 HP" run modifier, not only for a slider.

Worked example: `addons/spell_playground/playground_panel.gd`
(`_install_node_health_sets` / `_on_node_health_changed`), which seeds the
modifier from the baseline's own current value so installing the control changes
nothing until it moves. Two notes it also earns: a derived baseline reaches
every node through `NodeCombat._hp_pool`'s cap provider (#660) with no per-node
push, and a node with no owner falls back to its own stored base rather than to
the override.

---

## 4. A step function is a ladder of integers, never a logarithm

**Decision 2026-08-24 (#547).** A gameplay rule that steps up at round numbers is
a `ThresholdFormula` — an ascending `breakpoints` array compared with `>=` — not
`floor(log(x) / log(b))`.

`floor(log(INT) / log(10.0))` shipped as mana-per-turn and returned **2 at INT
1000** on glibc: `log(1000.0)` is `6.907755278982137`, one ulp below
`3 * log(10.0)`, the ratio is `2.9999999999999996`, and `floor` turns a last-bit
difference into a whole missing point of regen.

That is not a glibc bug to wait out. **IEEE 754 specifies only `+ - * / sqrt`
(and fma) to be correctly rounded** — `log`/`exp`/`pow`/`sin`/`cos`/`tan` are
each platform's own approximation, and they disagree in the last bits. `floor`
then amplifies any disagreement into a whole integer step, and `floor(log_b(x))`
sits exactly on an integer boundary precisely at `b^n` — the round numbers a
stat system lands on constantly. Since derived stats are recomputed **locally on
every peer** rather than sent (`docs/domain/multiplayer-sync-model.md`), a
Windows client and a Linux host silently disagree for a whole run, presenting as
"the client's caster runs dry a turn early" with nothing pointing at the network.

**Rejected: `round(log10(x))`.** It fixes INT 1000 by accident while moving every
breakpoint from `10^n` to `10^(n+0.5)` — INT 317 starts paying 3, INT 9 already
pays 1 — and leaves the libm dependence fully intact. A different curve, not a fix.

**Rejected: `str(int(x)).length() - 1`.** Exact, but a string allocation per
recompute in a pipeline that already appears in #470's profile, and it can only
ever express decades.

**How to apply:**

- Any monotone step function of one stat is authorable as breakpoints, not only
  decades: `[3, 8, 21, 55, 149, 404]` is exactly `floor(ln WIS)` for every
  integer WIS, because `ceil(e^n)` is where each step actually lands.
- **The ladder saturates at `breakpoints.size()`.** Extend it past anything the
  stat can plausibly reach, and pin the top rung in a test — a range that stops
  below the top of the array cannot see the saturation.
- Everything else stays a `RatioFormula` (`source / N` — a line; the INT stat floors once, #891) or a
  `LinearFormula`. See `.claude/rules/stats-system.md` → *Formula classes*.
- `mise run lint-transcendentals` fails on a new `log`/`exp`/`pow`/trig in a
  gameplay formula string or gameplay code path. Its allowlist is the record of
  which paths are presentation or transmitted-result, and **each entry states
  the condition under which its exemption stops being true** — write that
  condition, not "out of scope", if you add one.

---

## 5. An authored number is an overlay bin when a flat in the stat's unit is meaningless

**Decision 2026-09-21 (#912, owner).** A content resource — a spell's authored
range, a relic's flat bonus, anything a `.tres` says about *itself* — that wants
the stat pipeline to modify it is **not** a stat's base. It contributes its
number as one `ModifierBins` with `base_add = X` (`board = null`, no multipliers,
no SET) and hands it to the node-local read as an overlay:

```gdscript
node.get_local_value_with(stat_id, overlays)      # SkillNode passthrough
NodeCombat.get_local_value_with(stat_id, overlays)
```

Inside, the entity's bins, the node's bins and the overlays fold through
`Stat.get_value_with` — **one fold, one floor**, the same `(base + Σadd) ×
(1 + Σinc%) × Πmult + Σbon` every read runs, coerced once at the end (ADR 0016).
`get_local_value(id)` *is* `get_local_value_with(id, [])`; there is no second
merge path to drift from it.

**Why not write the number into `base_value`?** The base is the stat's own
(§3: the one door, and the def's policy runs on it). A spell's range written
there would be overwritten by the next spell's, would leak into every other
reader of the stat, and would make the board a mirror of whatever content was
last cast — the parallel-store smell. **Why not a `SET`?** A SET short-circuits
the fold: the whole point is that `% increased` and `MORE` on the stat apply *to*
the authored number, which only a base-side add gives.

**Contracts a caller relies on:**

- **Order.** Overlays fold strictly AFTER the node bins: sources are
  `[entity, node, overlays…]`, and an equal-priority SET tie goes to the later
  source, so overlay > node > entity. A real SET on the entity or node still
  wins over an overlay's `base_add` — a SET is a SET.
- **Tier 4 is `null`.** With no `Stat` under that id on either board there is
  nothing to coerce through, and the read answers `null` — never the def
  default, never `0`. The caller falls back to its own authored base (the number
  it put in the overlay). Only the bare `get_local_value` keeps the def-default
  tail, because a bare read has no base of its own to fall back to.
- **Accessor tokens ignore overlays.** `id__accessor` reads state (`current`,
  `wounded`, …), not a fold; overlays are silently not applied. Do not pass one
  expecting a merge.
- **The unit is the base's.** `+1` in `base_add` is a hop on a hop-ranged spell
  and a pixel on a euclidean one; `% increased` and `MORE` are unitless and
  apply to either. Keep the flat add's unit with the resource that authored it.

**Worked example — cast range (#1018).** `cast_range_hops` (INT) and
`cast_range_distance` (FLOAT) are base 0 on every board by contract. A
`HopRangeFinder` with `max_hops = 3` reads
`SpellRangeRules.reach(&"cast_range_hops", 3.0, attacker, source)`, which builds
one `ModifierBins` with `base_add = 3.0` and folds it through
`source.get_local_value_with` (tier 1), the caster's board's
`Stat.get_value_with` (tier 2, the tooltip's no-cast-from-node preview), or
answers the raw `3.0` (tier 3 — a null attacker, so an aura never inherits the
caster's reach; also a board with no such stat). So a node-local `+50%
increased cast_range_hops` yields `int(3 × 1.5) = 4`, a board `+2` yields `5`,
and a `SET 5` yields `5` for a 3-hop and a 10-hop spell alike. INT's own
contribution is authored on the boards as intrinsics on those stats — a flat
ladder on hops, a `% increased` line on distance — and lands in the same fold.

### The criterion: overlay-base stat or rate stat?

**The authored number is the stat's base when a flat in the stat's own unit is
meaningless without it** — `+1` to a range *multiplier* is not a hop, so
`cast_range_hops` is base 0 and the spell's `3` is the base every bin applies to.
**A rate stat keeps identity base `1.0`, and an `ADD_BASE +X` on it is a rate
bonus** — the authored number stays with its consumer, which multiplies it by
the composed rate. The premise that a flat bonus on spell damage "has nowhere to
go" only holds if the flat is measured in damage points; owner (2026-09-21,
#1016): it is measured in multiples of the authored number (`+1 spell_damage`
at INT 9 is +25% relative), and *"`power` sounds like a StatModifier (with
MULTIPLY operator) to be used as overlay for spell damage"* — the arithmetic the
code already runs. Audit verdict, 2026-09-21: none of these converts.

| Rate stat (base 1.0) | × authored number | Consumer |
|---|---|---|
| `spell_damage` (√INT intrinsic on the board) | `SpellDef.power` | `SpellResolver.impact_damage` — `get_local_value(&"spell_damage") × power` |
| `*_potency` (four) | `StatusDef.per_hit` | `StatusInstance` — `per_hit × potency × (1 − resistance)` |
| `healing_received` | the heal amount | `NodeCombat.heal_damage` — every heal passes through it |

One-line test for the next audit: *would `+1` on this stat, in the stat's own
unit, mean anything?* Hops, pixels, points → overlay base (§5). A multiple → rate
stat, leave it.

`PoolStat.base_provider` is the same idea aimed at a *cap* (a pool whose base is
computed elsewhere, then coerced); it is not folded onto this door.

