# Stat knobs and pool bins

Two authoring questions that keep getting re-derived from scratch, answered once.

- **"This rule needs a tweakable rate. Where does the knob live?"** → §1
- **"This pool needs a second bucket alongside `current`. How do I add one?"** → §2
- **"Why did writing `base_value` not trigger the ratchet?"** → §3
- **"This rule steps up at 10 / 100 / 1000. Can I just use a log?"** → §4 (no)

`.claude/rules/stats-system.md` is the *reference* — what exists, and how the
pipeline computes. This doc is the *decision procedure* for adding something new.

---

## 1. A tuning coefficient is a board stat

**Preliminary decision (2026-08-02, #298).** When a scaling rule needs a rate that
anything might want to tune, add an ordinary board scalar defaulting to `1.0` and
read it as a **formula input**. Leave `StatModifier.value` at its `1.0` identity —
the whole coefficient lives in the stat.

```
health      = 10 + core_health_scaling x CON     # D-26, #276
node_health = 10 + node_health_scaling x CON     # #298
```

Concretely, three files:

1. `stats_system/defs/<knob>.tres` — a `StatDef`, `value_type = 1` (FLOAT),
   `default_value = 1.0`, with a `modifier_name` that reads well in a tooltip
   ("Health per CON"). Copy `core_health_scaling.tres`.
2. `stats_system/stat_board.gd` — one `@export var <knob>: ScalarStat` in the
   matching group. **The field name must equal the stat id** (`get_stat` is
   `Object.get(id)`).
3. `entity/default_entity_board.tres` — the `ScalarStat` instance
   (`base_value = 1.0`), and an `ExpressionFormula` on the consuming intrinsic
   listing **both** ids in `inputs` (`"node_health_scaling * constitution"`).
   Miss the knob's id in `inputs` and moving the knob won't rebind — the modifier
   subscribes to exactly what `inputs` declares.

### Why a stat, and not a plain var somewhere

A knob-as-stat inherits four things for free, none of which a plain field gets:

- **Reactivity.** `StatModifier.bind()` subscribes to every input's
  `value_changed`, so moving the knob recomputes the target with no extra wiring.
- **Composability.** A CoreClass, a relic, an addon, an aura, *or a curse* all
  move it through the one modifier pipeline. This is the decisive one: the moment
  you want a lootable "+30% node HP per CON", a plain var has to grow a whole
  mechanism, and a stat already is one.
- **Authoring.** It shows up in the inspector and the stat-board visualizer.
- **Discoverability.** `AttributeRules` (`ui/hud/attribute_rules.gd`) *discovers*
  hover text by scanning intrinsics for `scales_with(attr_id)`, so the knob's
  effect surfaces in the Attributes Panel tooltip without being registered
  anywhere.

**It is also dirt cheap** — a `.tres` and one `@export`. That cheapness is the
argument: the answer scales to knob #2 and #3 with zero new machinery.

### The known cost, and the escape hatch

The board is a **flat namespace mixing two categories**: things an entity *has*
(`strength`) and coefficients of a *rule* (`core_health_scaling`). `StatDef` has
no `category` / `hidden` field to tell them apart — those were retired in #120
with `ui/stats_panel.gd`, deliberately.

That is a real smell, and the honest answer is that it does not compound:
**when knobs proliferate, adding a marker field to `StatDef` is a pure addition
with no migration** — because the knobs are already stats. Choosing a plain var
now and needing composability later *is* a migration. So the cheap option is also
the reversible one; take it, and revisit the tier when there are enough knobs to
see the shape.

Nothing auto-enumerates board stats, so a new knob surfaces nowhere uninvited.
If you *want* it visible, `addons/stat_board_visualizer/stat_board_graph.gd`
holds a hardcoded `_GROUP_LAYOUT` id list — add it there.

### The alternative that is a different *design*, not a different implementation

A CoreClass can already express "tankier" as an ordinary `INCREASE` modifier on
`node_health` — no new stat at all. That is a legitimate option, but it is not
the same number:

```
INCREASE   : (10 + CON) x 1.5     # scales the baked flat 10 too
coefficient: 10 + 1.5 x CON       # flat base stays fixed
```

D-21/D-26 chose the coefficient form for `health` on purpose, so the flat base
stays a fixed floor while only the attribute channel scales. Match it unless you
mean the other thing.

### When *not* to make a knob a formula input

Not every tunable is a coefficient. Existing board scalars are read three ways —
pick the one that matches:

| Shape | How it's read | Examples |
|---|---|---|
| **Formula input** | in an `ExpressionFormula`'s `inputs`, recomputes reactively | `core_health_scaling`, `node_health_scaling` |
| **Imperative** | plain GDScript read at the point of use | `ap_transfer_rate`, `dealloc_damage`, `crit_multiplier`, `initiative_speed` |
| **Pool rate pointer** | named on a `PoolStatDef` via `per_turn_stat_id`, consumed by `run_turn_upkeep` | `core_healing`, `mana_per_turn`, `wound_heal_per_turn` |

All three are still board stats, so all three stay class-tunable. Only reach for
a formula input when the value genuinely participates in computing another stat.

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
- Everything else stays a `RatioFormula` (`floor(source / N)`) or a
  `LinearFormula`. See `.claude/rules/stats-system.md` → *Formula classes*.
- `mise run lint-transcendentals` fails on a new `log`/`exp`/`pow`/trig in a
  gameplay formula string or gameplay code path. Its allowlist is the record of
  which paths are presentation or transmitted-result, and **each entry states
  the condition under which its exemption stops being true** — write that
  condition, not "out of scope", if you add one.
