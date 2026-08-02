# Stat knobs and pool bins

Two authoring questions that keep getting re-derived from scratch, answered once.

- **"This rule needs a tweakable rate. Where does the knob live?"** → §1
- **"This pool needs a second bucket alongside `current`. How do I add one?"** → §2
- **"Why did writing `base_value` not trigger the ratchet?"** → §3

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

## 3. The two `base_value` doors

`Stat.base_value`'s setter emits `value_changed` but does **not** run
`PoolStat._apply_max_change()`. That method is only reachable from
`add_modifier` / `remove_modifier` / `_on_dependent_modifier_changed`.

**This is deliberate, not an oversight.** A raw `base_value` write is the door for
moving a cap *without* the D-21 ratchet, and three callers depend on it:

- `SkillPointStat.claim(n)` — max grows, `current` does not; the new SP lands in
  `used`. This is exactly what distinguishes `claim` from `grant`, and
  `AllocationSystem` calls it on **every allocation**.
- `GrowablePoolStatDef` growth — a level-up must not also trigger
  `heal_on_max_increase`.
- `SkillNode._ensure_local_stat` — seeding a fresh combat pool's base while
  `current` is still 0.

So there are two doors, and you must pick:

| Door | Call | Cap-change behaviour |
|---|---|---|
| **Raw** | `stat.base_value = v` | none — no grant on a rise, no clamp on a fall |
| **Ratcheted** | `pool.set_base_ratcheted(v)` | routes through `_apply_max_change` → `on_max_increased` / clamp |

**How this bit us (#346).** `SkillNode._sync_combat_health_base()` used the raw
door to follow the owner's `node_health` baseline. So as CON climbed with level,
every allocated node's cap rose while `current` stayed frozen, and node regen
(~1/turn) could not close a gap that kept widening — nodes drifted toward reading
near-empty and never recovered. The fix was to use the ratcheted door, *not* to
weld the raw one shut: doing that would have made every `claim(1)` also mint a
spendable SP, silently, on the hottest path in the game.

**How to apply:** if you are moving a pool's `base_value` and the pool has a
meaningful `current`, you almost certainly want `set_base_ratcheted`. Reach for
the raw write only when you can name why the cap should move without the current
following — and leave that reason in a comment, as `claim()` does.
