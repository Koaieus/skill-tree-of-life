# Stat System Design — Skill Tree of Life

---

## Context & Goals

This game's skill tree IS the game. Entities (players, NPCs) live on the tree and own nodes. Skill nodes carry **stat modifiers** — the core editorial loop is:

> Designer opens a SkillNode → picks a stat (e.g. ATTACK\_SPEED) from a list → picks an operator (+%, ×, +flat) → enters a value → done.

Everything downstream of this (runtime application, UI display, type safety) should serve that loop, not complicate it.

---

## What Was Learned from EnhancedStat (Zennyth)

**What worked well:**
- Defining a stat = subclassing a `Stat` base class. Class composition is free. Behavior specific to a stat (e.g. `InitiativeStat.progress_initiative()`) lives right there, one file.
- The reactive pipeline: value changes propagate automatically.
- The bind mechanism: stat → node property, live.

**What didn't port cleanly:**
- The `stat_key: GDScript` pattern — using a script object as a dictionary key is clever but fragile. Renaming or moving a file silently breaks lookups.
- `StatMetaDataRepository`: a dictionary mapping class names to metadata that the editor would periodically wipe, requiring a manual "Populate" button to restore. This is a red flag that the architecture is fighting Godot's resource system rather than working with it.
- No `abstract` keyword in the Godot 4.1 era it targeted — override chains for `_compute()` etc. were messy and hard to enforce.
- Editor inspector integration for the modifier picker was provided by a custom `EditorInspectorPlugin`, which was the good part — but heavy infrastructure for one dropdown.

---

## Design Tensions (Unresolved)

### 1. Stat as class vs stat as resource

**Class approach (Zennyth-style):**
- Pro: method overrides, behavior local to the stat, class composition, type-safe `is` checks
- Pro: `InitiativeStat` can have `progress_initiative()` right on it
- Con: metadata (name, label, description, display order) requires either a repository lookup OR overriding a method per stat — both feel wrong
- Con: the GDScript-as-key problem

**Resource approach (proposed v2):**
- Pro: define once in a `.tres`, editor fills in name/description/display naturally
- Pro: no repository dict that gets cleared
- Pro: stats board is just a resource referencing other resources — Godot handles the persistence
- Con: no method overrides — a `HealthPoolStat` can't add `deplete()` directly
- Con: loses the clean class hierarchy for isinstance checks

**Current lean:** Resources for *definition* (what a stat IS — its name, type, range, display), classes for *runtime behavior* (how it computes, what signals it emits). The definition is the single source of truth for the editor; the runtime object is created from it.

### 2. Pool stats

A pool stat (Health, XP, Skill Points) has:
- A **current value** (can go up/down at runtime)
- A **max value** (itself a first-class stat in the registry, with its own ID, modifiable via normal modifier routing)
- Optional: growable max (XP leveling)

**Key resolved decision: pool max is a first-class stat.**

The `max` of a pool stat is not a sub-field — it is a sibling `RuntimeStat` with its own ID in the registry. Example:

```
health      → PoolStatDef   { max_id: &"health_max" }
health_max  → StatDef       { value_type: INT }
```

A node modifier that increases max health is simply:
```
StatModifier { stat_id: &"health_max", operation: ADD_FLAT, value: 1 }
```

No special syntax. No sub-stat notation. The `RuntimePoolStat` holds a typed reference to the `RuntimeStat` for its max, and listens for changes:

```gdscript
max.value_changed.connect(_on_max_changed)

func _on_max_changed(new_max: int) -> void:
    if current > new_max:             # max went DOWN — clamp current
        set_current(new_max)          # emits depleted / changed
    elif heal_on_max_increase:        # max went UP and policy says heal
        set_current(current + (new_max - previous_max))
```

`heal_on_max_increase: bool` is a flag on `PoolStatDefinition`. Default **true** for health (gaining max HP heals you for the difference — standard RPG feel). Default **false** for skill points (gaining max SP expands capacity but doesn't immediately give you a free point — the player earns that through the economy).

**Options considered for pool structure:**
- `is_pool: bool` flag on the definition, runtime creates two holders
- Separate `PoolStatDefinition` subclass of `StatDefinition` — keeps the resource approach but adds pool-specific exports (`is_growable`, `max_stat_id`, `heal_on_max_increase`)
- Keep pool stats as a class (`IntPoolStat` etc.) as they exist now, but source their *metadata* from a definition resource

The pool case is the strongest argument for keeping some class hierarchy — pools have meaningfully different runtime behavior (clamping, deplete/replenish signals, level-up on grow) that doesn't fit in a data resource cleanly.

**Current lean:** Hybrid. `StatDefinition` resource for scalar stats. `PoolStatDefinition` extends `StatDefinition` with pool extras. Runtime classes still exist but are slimmed down and driven by their definition.

**On minimums:** `health_min` could in principle follow the same pattern as `health_max` — a first-class stat in the registry, targetable by modifiers (e.g. a "minimum survivable HP" defensive passive). For now, minimum is a fixed value (`min_value: int = 0` on `PoolStatDefinition`), not a separate stat. Promote to a stat ID pattern if and when a designer needs it.

### 3. The stats board (EntityStats)

Every entity needs a "board" — a structured set of stats. Currently `EntityStats extends Stats` with typed `@export` fields per stat. This is good for type safety and editor visibility but creates a problem:

- Players have all entity stats + some player-only ones
- NPCs have a subset (or same set, cheaper to just give all)
- Anything that *provides* stats (a StatsManager or component) needs to be type-safe for whichever board it wraps

Current v1 approach: `EntityStats` base + `EntityStatsManager` wrapping it. `Player extends TreeEntity` gets the manager. The typed `_stats: EntityStats` gives compile-time access.

The risk: if you want to reuse the panel UI or a modifier system, they need to know "does this entity have health?" — which requires either an interface (no interfaces in GDScript), a duck-typed `has_stat()` call, or trusting the type.

**Current lean:** Keep the typed board per entity category. Accept that `StatsManager` is generic and callers downcast when they need specifics. Use `abstract` (Godot 4.4+) to enforce the board interface.

---

## Proposed v2 Direction

### Core objects

```
StatDefinition (Resource)
  - id: StringName          # &"attack_speed" — stable, refactor-safe
  - display_name: String    # "Attack Speed"
  - description: String
  - value_type: enum {INT, FLOAT, BOOL}
  - display_order: int
  - display_type: enum {BASIC, BAR, PROGRESS}
  - tint_color: Color

PoolStatDefinition extends StatDefinition
  - max_id: StringName          # references another StatDefinition — that stat IS the max
  - min_value: int              # fixed floor, default 0
  - is_growable: bool
  - heal_on_max_increase: bool  # does gaining max also heal current by the delta?
  - growth_formula: ...         # TBD — Callable or GrowthCurve resource

StatRegistry (Autoload Resource)
  - definitions: Array[StatDefinition]   # the single source of truth
  - func get(id: StringName) -> StatDefinition
```

### Runtime stat objects

Slim, created at game start from definitions. No GDScript-as-key.

```
RuntimeStat
  - definition: StatDefinition     # back-reference for display
  - base_value: Variant
  - _modifiers: Array[StatModifier]
  - signal value_changed
  - func get_value() -> Variant    # applies modifiers, rounds if INT
  - func add_modifier(m: StatModifier)
  - func remove_modifier(m: StatModifier)
```

Pool gets a subclass because the behavior IS different:

```
RuntimePoolStat extends RuntimeStat
  - current: float
  - max: RuntimeStat              # sibling stat, its own ID in registry
  - signal depleted / replenished / changed(current, max)
  - func deplete() / replenish() / set_current(v)
```

### Modifier definition (on a SkillNode)

```
StatModifier (Resource)
  - stat_id: StringName         # matches StatDefinition.id — including pool max IDs like &"health_max"
  - operation: enum {ADD_FLAT, ADD_PERCENT, MULTIPLY, SET}
  - value: float
```

This is what the designer sets in the inspector. No class file per stat. The `stat_id` field is what an `EditorInspectorPlugin` turns into a dropdown (populated from `StatRegistry`). Before the plugin exists, it's just a StringName — typos are possible but at least they fail loudly at runtime rather than silently.

### Stats board

```
abstract class StatsBoard extends Resource
  func get_stat(id: StringName) -> RuntimeStat: abstract
  func get_stats() -> Array[RuntimeStat]: abstract
  func add_modifier(mod: StatModifier): abstract

class EntityStatsBoard extends StatsBoard
  # typed fields for editor visibility + type safety
  @export var strength: RuntimeStat
  @export var health: RuntimePoolStat
  @export var initiative: RuntimeStat
  # ...

class PlayerStatsBoard extends EntityStatsBoard
  @export var skill_points: RuntimePoolStat
  # player-only extras
```

### Modifier application order

Keep the current approach (application_order int, sort before applying). ADD_FLAT < ADD_PERCENT < MULTIPLY is a sensible default order. Make it configurable per modifier if needed.

---

## Per-Turn Stat Pairs — Architecture Pattern

Many stats have a "per turn" counterpart: `heal_per_turn`, `sp_gain_per_turn`, `xp_gain_per_turn`. Not all stats get one, but enough do that the pattern should be principled.

**Design question:** model each `_per_turn` counterpart as a separate stat, or build a generic pairing into the stat system?

### Option A — Separate stats (current approach)
`health` and `health_per_turn` are two independent entries in the registry. The turn system reads `health_per_turn.get_value()` and calls `health.replenish(that_amount)` each tick.

- Pro: maximum flexibility — `health_per_turn` can have its own modifiers, its own display, its own modifier list
- Pro: no new abstractions needed
- Pro: the turn system is a simple consumer; it doesn't need to understand pairing
- Con: the registry grows. Ten pool stats = potentially twenty entries.
- Con: the designer must remember to create both halves and name them consistently.

### Option B — Paired stat definition
`PoolStatDefinition` gains a `regen_id: StringName` field pointing to the per-turn scalar. The registry enforces the pair.

- Pro: the pairing is explicit and discoverable in the editor
- Pro: UI can show "health: 40/80 (+3/turn)" from one query
- Con: adds complexity to the definition layer
- Con: not all pools have regen; not all regen stats have pools

**Decision: Option A for now.**

Rationale: keep the stat layer dumb. The *semantic* pairing (health + health_per_turn) is captured in naming convention and in the turn system's code, not in the data model. If the UI needs to display the pair together, pass both stat IDs to the widget — no architecture change needed. Revisit if the registry gets unwieldy.

**Naming convention:** `{pool_id}_per_turn` is the canonical suffix. Examples: `health_per_turn`, `sp_per_turn`, `xp_per_turn`. The turn system can discover all per-turn stats by suffix scan if needed, or list them explicitly (explicit is better for a small list).

**Which stats get a per-turn counterpart:**

| Pool Stat | Per-Turn Stat | Notes |
|---|---|---|
| `health` | `health_per_turn` | HP regen. Can be negative (DOT effect via modifier). |
| `skill_points` | `sp_per_turn` | SP income. Core passive loop. |
| `xp` | `xp_per_turn` | XP income. Passive accumulation. |
| `deallocation_points` | — | Resets to a per-turn budget each turn (see Movement); not a regen loop. |
| `initiative` | — | Initiative has its own progress mechanic, not a regen loop. |

Stats that do NOT get per-turn versions: all scalars (`strength`, `dexterity`, `intelligence`, `movement_speed`, etc.). These are capability stats, not resource pools. They change through modifiers (node allocation/deallocation), not through ticking.

---

## What Stays from v1

- `TreeNode` / `TreeGraph` / `Navigator` — largely fine, independent of stat system
- `TurnManager` — fine
- The VFX beam on allocation — keep
- `StatBind` concept — keep, just rebind to new RuntimeStat
- `StatMetaData.display_type` → drives widget selection — keep the concept, fold into `StatDefinition`

## What Goes Away

- `stat_key: GDScript` everywhere
- `StatMetaDataRepository` (the fragile dict autoload)
- The parallel `IntStat / FloatStat / BoolStat` class hierarchy for the *value type distinction* — that's now a flag on the definition
- `_computed_stat.gd` override chain for `_compute()` — one `RuntimeStat._compute()` handles all scalar types

---

## Naming Convention (Resolved)

| v1 name | v2 name | Rationale |
|---|---|---|
| `StatMetaData` / `StatDefinition` | `StatDef` | Short, clear, "Def" implies blueprint not instance |
| `RuntimeStat` | `Stat` | The thing you interact with at runtime IS just "a stat" |
| `StatMetaDataRepository` | `StatRegistry` | Gone as a fragile dict autoload; replaced by a `.tres` asset loaded once |
| `StatsManager` | `StatsComponent` | "Manager" implies coordination; this is just a component on an entity |
| `EntityStats` | `StatBoard` | More neutral, works for players and NPCs alike |

**Risk flag:** `Stat` as a class name is generic. If a future Godot version or plugin uses it, you collide. Mitigation: GDScript class names are project-local, so collision only happens with autoloaded singletons or C# interop. Acceptable risk.

---

## Stat Boards — Decision Summary

### One stat vocabulary, shared by all entities

Players and enemies are both entities on the tree. They are the same kind of thing mechanically. The tree applies the same modifier rules regardless of who owns a node.

**Decision: Option A (full board, everyone gets all stats).** Every entity instantiates every stat from the registry. NPCs with no `skill_points` use just have it at zero, hidden from UI. This lets modifier routing be trivially safe — `stat_id: &"strength"` always finds a target.

Graduate to Option C (typed inheritance with `PlayerStatBoard extends EntityStatBoard`) once the stat list stabilizes after the first playable slice.

### Modifier routing

```gdscript
for mod_def in node.modifiers:
    var stat: Stat = entity.stats.get(mod_def.stat_id)
    if stat == null:
        push_warning("Entity %s has no stat %s" % [entity, mod_def.stat_id])
        continue
    stat.add_modifier(mod_def)
```

Under Option A, `stat` is never null. The warning is a safety net for mistyped stat IDs during development. Under Option C (future), it fires for player-exclusive stats applied to NPCs — which should not happen by designer contract.

### The same tree means entity-agnostic modifiers

`StatModifier` says "+10 STR." Whoever owns the node gets +10 STR. The tree doesn't care who you are. This is correct and elegant.

---

## Modifier Application — Operator Semantics

For the designer loop: pick a stat, pick an operator, enter a value.

| Operator | Symbol | Meaning | Example |
|---|---|---|---|
| `ADD_FLAT` | `+N` | Adds N to base value | `+10 STR` |
| `ADD_PERCENT` | `+N%` | Adds N% of base value (additive with other +% mods) | `+20% STR` |
| `MULTIPLY` | `×N` | Multiplies total after all additive mods | `×1.5 STR` |
| `SET` | `=N` | Overrides to exactly N (use sparingly) | `=1 movement_speed` |

**Application order:** `ADD_FLAT` first → `ADD_PERCENT` second → `MULTIPLY` last. This is the Path of Exile model. "More" (multiply) is strictly stronger than "increased" (add percent), which prevents percent stacking from being trivially overpowered.

**Type matching:** `ADD_FLAT` and `ADD_PERCENT` on an INT stat always produce an INT result (round after all mods applied, not per-mod). FLOAT intermediate arithmetic is fine; the final `get_value()` call rounds if `value_type == INT`.

---

## The Core — Stats and Aura

The core is a component that sits on top of a node. It has its own stats (separate from the entity's stat board — or a subset of it used to calculate the aura it projects).

**Core aura:**
- The core radiates a bonus to owned nodes within range (measured in hops, euclidean radius, or a shell band — per the core's class).
- Aura strength falls off with distance. The falloff curve is a core parameter (upgradeable).
- Example: core with `aura_range: 2` and `aura_strength: 5` adds +5 to adjacent owned nodes and +2 to nodes 2 hops away (falloff halves each hop, rounded).
- **The aura is the answer to the "safe core" problem.** An entity could hide its core on a distant, safe filament and become hard to kill — but then no fighting node receives the aura, so the build underperforms. The aura is the carrot that drags the core toward the front line, and shaping it (boost near / boost a 3–5 hop shell / boost-more-the-further-out) is most of where a core *class* gets its identity. (See lore: The Core; combat: the safe-core problem.)

**Core node as the kill condition:**
- The core node is the node the core currently occupies.
- **Death condition = `health` pool depletion**, *not* core-node loss (reframed — see `combat_system.md` Core-on-node health). The core node can never be *islanded away* (the islanding rule keeps the core's piece as the entity), so "lose the core" only ever meant "deplete the pool." Other nodes can be lost and recovered; the core node cannot be surrendered.
- The core node carries a **recharging shield** (its `node_health`, resets each owner turn) over the **persistent `health` pool**. To grind the core you must out-damage its shield within one round and overflow into `health`. `core_health` **folds into `health`** as a class-upgradable base/bonus rather than a separate pool — trimming the stat table. The persistent `health` pool is thus depleted **two ways**: arm-loss (`health.decrease(N)`) and core-shield overflow — the single decisive attrition clock.

**Entity = connected subgraph; core = nucleus.** Because an entity is just the connected set of nodes it owns, an attack that deallocates a bridge node would otherwise split it in two. The core resolves this: the piece holding the core stays the entity, every orphaned piece becomes an island (one-turn grace, else dissolves). This is why a cut entity doesn't spawn a second entity — there is exactly one nucleus.

**Health loss proportional to arm size:**
When a connected sub-graph of N nodes is severed from the entity's constellation, the entity takes health damage proportional to N. Larger arm cut off = more health lost. This is a direct call: `health.decrease(severed_node_count)`. It is not special-cased — it uses the normal pool stat depletion path, triggering all the same signals.

The severed nodes' modifiers are also removed from the entity's stat board in the same operation. Losing a cluster of STR-heavy nodes literally makes the entity weaker, not just smaller.

---

## The Health / Node Loss Model

Health is structurally tied to the entity's presence on the tree.

**Design intent:**
- Losing a cluster of N nodes → `health.decrease(N)`.
- The N skill points spent on those nodes are not immediately refunded. They drip back at `sp_per_turn` per turn.
- This prevents "get hit, instantly buy back, zero consequence" loops.
- `health_per_turn` is itself a stat, modifiable by nodes. A defensive build would stack it.

**Architecture implication:**
- `health` is a `RuntimePoolStat`. `health_max` is a sibling `RuntimeStat` targeted by node modifiers via `stat_id: &"health_max"`.
- `health_max` changing fires `_on_max_changed` on the pool, which clamps or heals current as appropriate.
- Node severance fires `health.decrease(n)` and does not otherwise special-case health. The pool's normal signal chain handles everything downstream (UI update, death check, etc.).

---

## Per-Node Health — The Combat Layer

The combat design introduces a distinction the stat layer must support: an entity has an aggregate `health` pool (the structural arm-loss model above), but **individual nodes also have their own small HP** for the moment-to-moment business of being attacked.

- `node_health` / `node_health_max` — a small per-node pool (base placeholder 1–3 vs. 10; set in Balance). When a node's current HP hits 0, the node is deallocated → island/grace check → the aggregate `health.decrease(N)` path fires for any arm that drops.
- This is *not* a board stat in the same sense as the entity-wide stats. It lives per-node, and its max is driven by the owning entity's aggregate (entity totals set the baseline; addons like Reinforcement and per-node modifiers vary it). Architecturally this is the cleanest as a `RuntimePoolStat` instance held by the `TreeNode`'s combat component, seeded from the entity board + node addons, rather than a single registry entry.

**The reset rule — ephemeral vs. persistent *(LOCKED; see `combat_system.md` — Node HP).*** `node_health` is **ephemeral**: it resets to `node_health_max` **at the start of its owner entity's turn** (not at the end of every turn). The entity-aggregate `health` pool is **persistent** and does *not* reset. The two layers must be kept strictly separate in the architecture — the per-node reset signal must never touch the `health` `RuntimePoolStat`. Mechanically `node_health` now means *"how much damage must converge on me in one round to kill me"* (a per-round **focus-soak** gate), not durability-over-time.

- **Implementation:** each owner-turn-start, the turn system calls `set_current(max)` (equivalently `replenish` to full) on every owned node's `node_health` pool. Enemy nodes do not reset during the owner's turn, so two actions stack within a turn (dent-then-finish); a node's wounds persist across the enemy phase, enabling multi-attacker focus-fire.

**The core node — a recharging shield over the persistent pool *(LOCKED).*** The core node's `node_health` acts as a **recharging shield** in front of the entity `health` pool:

- Attack order on the core node: `armor/resist → node_health (shield) → overflow-this-round → health (persistent)`.
- The core node's shield resets to full at owner turn start like any node, but it **never force-deallocates the core** (unlike a normal node at 0 HP). **0 shield is a legal transient state** — at 0, post-mitigation damage routes straight into `health` for the rest of the round; the shield recharges next owner-turn-start.
- Architecturally: the `TreeNode` combat component's `node_health` pool, when the node is the core seat, overflows its excess `decrease()` into the entity board's `health` pool instead of triggering severance. `core_health` is **no longer a separate pool** — it folds into `health` as a class-upgradable base/bonus. The **death condition is `health` depletion**, not core-node loss (the core can never be islanded away).

**Open:** do we model `node_health` through the same `StatDefinition`/registry machinery (a per-node `RuntimePoolStat` whose max is computed) or as a lighter-weight field on the node's combat component? Leaning: reuse `RuntimePoolStat` so the signal chain, clamping, and the per-turn reset/overflow all come for free, but seed it per-node rather than from a single shared board stat.

---

## Movement as Stats

Movement on the tree is **two distinct things** and wants two stats. (Confirmed in the combat doc; this extends the older single-stat framing.)

### `movement_speed` (core relocation)
`movement_speed` (INT scalar, default 1) is consumed to hop the **core** along owned edges.

- The core hops from its current node to an adjacent owned node. Each hop costs 1 movement point.
- Movement points reset each turn.
- The core cannot move through unallocated or enemy-owned nodes without triggering combat rules.

### `deallocation_points` (constellation reshaping / "apparent movement")
`deallocation_points` (INT, a small per-turn budget) governs how much the entity can **reshape** itself per turn: deallocate here, reallocate there. This is how a body "moves" across the tree without anything physically sliding — the allocation frontier reaches a new direction (the PoE-refund analogy).

- Resets to its budget each turn (same reset pattern as movement points).
- A "fast" build pushes `movement_speed` and/or `deallocation_points` to ~4–6, which is genuinely zippy at this scale.
- Keeping the two separate is deliberate: a build can be mobile *within* its body (high `movement_speed`) yet slow to *expand/relocate* (low `deallocation_points`), or vice versa.

**Implication for `StatsComponent`:**
Neither is special-cased — both are stats the movement/turn systems read.
`MovementSystem.get_available_hops(entity) → entity.stats.get(&"movement_speed").value`
`MovementSystem.get_dealloc_budget(entity) → entity.stats.get(&"deallocation_points").value`

---

## Node Component System — ECS Addons

Nodes support **attachable components** that modify behavior beyond the base stat modifier list. This is an ECS-flavored layer sitting on top of the existing node type.

An **addon** is a `Resource` with a defined interface. Nodes hold `Array[NodeAddon]`. The addon system affects how a node *behaves on the tree*, not what stats it grants — stats are on the modifier list, behavior is on the addon list.

```
NodeAddon (Resource)
  - func on_allocated(node: TreeNode, entity: TreeEntity): virtual
  - func on_deallocated(node: TreeNode): virtual
  - func on_tick(node: TreeNode): virtual

ArmorRingAddon extends NodeAddon
  - damage_reduction: int   # flat DR applied to attacks targeting this node

WinchAddon extends NodeAddon
  - pull_strength: float    # spring-like force drawing adjacent nodes inward
  - pull_range: int         # hop distance of effect

ReinforcementAddon extends NodeAddon
  - health_bonus: int       # adds to node's effective HP

BufferAddon extends NodeAddon
  - reach: int              # attack-time reach budget (scaled by pressure_capacity)
  # behavior: a tap TEMPORARILY allocates existing field nodes for reach (melee pivot /
  # ranged stubs / magic hub-degree), then the buffer goes on cooldown. Reverts at turn
  # end unless promoted in Consolidation. NOT melee fuel — see skill_node_addons.md.

GateAddon extends NodeAddon       # 2-component: spans TWO endpoint nodes (paired/shared)
  - endpoint_a: TreeNode
  - endpoint_b: TreeNode    # both within euclidean range X; no existing gate between them
  - powered: bool           # toggle at will: depower an existing edge / create a temp edge
  # FULLY REVERSIBLE (on removal / endpoint death → revert). Self-islanding allowed (warn).
  # Persistence-on-turn-end OPEN (lean persist). See skill_node_addons.md (Gate).

SpikesAddon extends NodeAddon     # raises the node's vertex-spike contribution in a blade
  - spike_power: int        # offensive: adds to the face/vertex term (confirmed)
  # defensive structural model (attack incoming blade edges / de-rigidify) is OPEN;
  # reconcile with thorns (one stat or two?) before shipping. See skill_node_addons.md (Spikes).
```

**Design constraint:** addons are applied to specific nodes by the designer (or by loot drops). They are not on the stat modifier list and do not flow through the modifier pipeline. Their effects are resolved by the systems that care about them (combat system reads `ArmorRingAddon` and `BufferAddon`, physics system reads `WinchAddon`, etc.).

**Open question:** can addons be stacked on a single node? Multiple armor rings? Probably yes with diminishing returns, but this needs a design pass before committing to an architecture for it.

---

## Stat Vocabulary (Canonical List, v2)

This table is the **source of truth** for stat IDs; the combat doc mirrors a combat-relevant subset for context. All entities share this board. Pool stats list their max sibling ID. Per-turn counterparts listed where they exist.

| Stat ID | Type | Kind | Per-Turn Sibling | Notes |
|---|---|---|---|---|
| `health` | INT | Pool | `health_per_turn` | Current/max HP (entity aggregate). **Persistent — does not reset.** The single **death clock** (depletion = death). Depleted two ways: arm-loss (`health.decrease(N)`) and **core-shield overflow** (damage that breaks the core node's `node_health` shield in one round). **`core_health` folds into this** as a class-upgradable base/bonus (no longer a separate pool). |
| `health_max` | INT | Scalar | — | Max of the health pool. Target of `+max health` modifiers. |
| `health_per_turn` | INT | Scalar | — | HP regen per tick. Can be negative (DoT). |
| `node_health` | INT | Pool (per-node) | — | Per-node HP (base placeholder 1–3 vs. 10; Balance). 0 → node deallocated (except the core node — its `node_health` is a shield; see below). **Ephemeral: resets to max at the start of its owner's turn** (focus-soak — "damage that must converge in one round to kill me"). Seeded per-node, not a shared board entry. |
| `node_health_max` | INT | Scalar (per-node) | — | Per-node HP cap; driven by entity totals + addons (Reinforcement) + CON. The per-round focus-soak threshold. |
| `node_health_per_turn` | INT | Scalar (per-node) | — | **Superseded — GitHub #13 resolved by the owner-turn-start reset.** The "what happens to nodes that don't die?" question is answered structurally: a node's `node_health` **fully resets to max at its owner's turn start**, so no dent survives into the owner's own turn and no gradual regen stat is needed. Wounds persist only *within a round* / across the enemy phase (enabling multi-attacker focus-fire), then reset. Keep this row only if a future mechanic wants *mid-round* node recovery; not part of the baseline. |
| `skill_points` | INT | Pool | `sp_per_turn` | Current/max SP. Spent on allocation. |
| `skill_points_max` | INT | Scalar | — | Max SP capacity. Grows on level-up. |
| `sp_per_turn` | INT | Scalar | — | SP income per tick. Core passive loop. |
| `xp` | INT | GrowablePool | `xp_per_turn` | XP toward next level. Max grows on level-up via formula. |
| `xp_per_turn` | INT | Scalar | — | Passive XP income per tick. Primarily from White (W) nodes — the economic lifeblood. |
| `initiative` | INT | Scalar+progress | — | Turn order. Has a `progress` sub-value (0–100) filled each tick. |
| `movement_speed` | INT | Scalar (resets) | — | Hops the core can relocate per turn. Default 1. |
| `deallocation_points` | INT | Scalar (resets) | — | Per-turn reshape budget (apparent movement). Default small. |
| `action_points` | INT | Scalar (resets) | — | **Attacks per turn. Default 2** (LOCKED). Second action finishes the first's dent before the owner-turn `node_health` reset (commit-vs-pivot read). Ranged stays one volley/turn; the second action can be a different mode stacking on one node. More-than-2 only via **ultra-rare** `action_points` node modifiers (chase item, in the spirit of `bonus_hop_count`) — not default. Read by `TurnManager`. |
| `strength` | INT | Scalar | — | Melee (R/Red). `STR//10` per contact; blade size `STR//10+1` nodes. |
| `dexterity` | INT | Scalar | — | Ranged (G/Green). `DEX//10` per firing leaf. Possibly dodge. |
| `intelligence` | INT | Scalar | — | Magic (B/Blue). `INT//10` per damage instance — **potency, never reach**. |
| `constitution` | INT | Scalar | — | **CON (White).** Durability — drives `node_health` only, linearly (`+1 per 10 CON`, TBD #268). Does **not** touch `armor` or `min_damage_taken` — those stay battlefield-found (D-11). Levelling grants CON (D-14), so durability scales with level. No attack. Implemented #269. |
| `wisdom` | INT | Scalar | — | **WIS (Gold).** XP-gain rate; carries growth modifiers. The economy attribute (supersedes White=XP). |
| `perception` | INT | Scalar | — | **PER (Purple).** Vision + sensor range. `+1 sense_range / 10 PER`, `+2% vision_range / PER`. |
| `bonus_hop_count` | INT | Scalar | — | Magic **reach** (the only source). Ultra-rare (~1–2 on the map). Default 0. |
| `luck` | INT | Scalar | — | Scales roguelike fortune mechanics. **Modifier draft pool size = 3 + `luck`** (at level-up; see `entity_stat_board_prototype.md`). Also skews loot table quality and damage RNG: rolls on `N–M` damage ranges are biased toward `M` proportionally to `luck`. Default 0. |
| `coolness` | INT | Scalar | — | Prestige only — no mechanical effect; end-credits tally. The "all edge, no point" stat. |
| `attack_range` | INT | Scalar | — | Max euclidean range for **ranged** only. Magic reach is `bonus_hop_count`. (Relay addon TBD.) |
| `pressure_capacity` | INT | Scalar | — | **Attack-time reach budget**: existing field nodes a buffer tap can temporarily allocate. (No longer melee charge count — melee size is `STR//10+1`.) |
| `crit_chance` | INT | Scalar | — | Percent chance to crit. Global across attack types for now. Keep low (5–10%). |
| `crit_mult` | FLOAT | Scalar | — | Crit damage multiplier. Default ×2. (FLOAT exception — it's a multiplier.) |
| `armor` | INT | Scalar | — | Flat damage reduction (all types). Floor leaves ≥1 damage through. |
| `resist_r` | INT | Scalar | — | Damage reduction vs. melee (Red). |
| `resist_g` | INT | Scalar | — | Damage reduction vs. ranged (Green). |
| `resist_b` | INT | Scalar | — | Damage reduction vs. magic (Blue). |
| `core_charge_capacity` | INT | Scalar | — | Cap on extraction charges (default 3). +1 charge per enemy core killed. |
| `aura_range` | INT | Scalar | — | Core only. Hops/radius of core aura projection. |
| `aura_strength` | INT | Scalar | — | Core only. Bonus strength of core aura per hop (before falloff). |

**Notes:**
- All scalars are INT for 85%+ of stats. FLOAT reserved for percentage multipliers internal to the modifier system, and the explicit exception of `crit_mult` — not exposed as raw stats elsewhere.
- BOOL stats exist (e.g. `is_infinite` on skill points for debug/testing) but are rare and probably editor-only.
- `skill_points` being a pool stat is intentional: `current` = spendable, `max` = capacity. Gaining SP means current += 1 AND max += 1. Spending costs current only. `heal_on_max_increase` is **false** for SP — expanding capacity does not auto-gift a point.
- `movement_speed` and `deallocation_points` both reset each turn rather than accumulating like a resource pool. Open Q9 (movement points as pool vs scalar reset) applies to both.
- `node_health` is the per-node combat HP and lives on each node's combat component, seeded from entity totals + addons — distinct from the entity-aggregate `health` pool. See *Per-Node Health*.
- `resist_r/g/b` implement the rock-paper-scissors combat triangle. The triangle is **emergent**: a Red-heavy entity that happens to carry `resist_b` is naturally tough against Blue (magic), but if it didn't build that resist it should consider respeccing when it meets an INT-heavy opponent. This emerges from build choices, not hardcoded matchups.
- `aura_range` and `aura_strength` only exist meaningfully on entities with a core. Under Option A (full board), these sit at zero on non-core entities; the core system only reads them for core-bearing entities. Under Option C (future), they'd live on a `CoreStatBoard`.

---

## Combat — Node Type Triangle

The RGBW node type system creates a combat identity for entities and individual nodes.

Six colors: three attack (prevalent), three utility (rarer). The attack triangle lives in R/G/B; White/Gold/Purple carry no attack slot.

| Color | Attribute | Attack | Strong vs. | Weak vs. |
|---|---|---|---|---|
| Red | Strength | Melee — phantom blade (adjacency) | B (Magic) | G (Ranged) |
| Green | Dexterity | Ranged — leaf volley, long range | R (Melee) | B (Magic) |
| Blue | Intelligence | Graph-magic — hops along edges | G (Ranged) | R (Melee) |
| White | Constitution | None — durability | — | — |
| Gold | Wisdom | None — XP / growth | — | — |
| Purple | Perception | None — vision / sensing | — | — |
| X (Other) | — | None | — | — |

**X (Other)** is a placeholder type for mystery / keystone / special nodes (rule-changers, sockets) — not yet specified. See GDD §3. It carries no attack and no triangle slot.

**Rock-paper-scissors logic (R › B › G › R):** R beats B (brute force closes the distance and crushes the wizard before magic matters), B beats G (magic outranges and disrupts the archer), G beats R (ranged kites the melee bruiser, who can't reach). *(Canon: R>B>G>R.)*

The utility colors are combat-neutral. **Gold (WIS)** is the new economic lifeblood — XP/turn → SP income (this role was formerly White's). **White (CON)** is durability (node/core HP, armor-affix weight). **Purple (PER)** is sensing. A growth/knowledge-heavy build is rich but militarily helpless without allied RGB nodes — which is why Gold (and the old White-as-economy) nodes are fought over as objectives. **Procgen clusters like-colors into biome-like regions** (Red territory, Blue territory) — color is *content identity*, not an adjacency-coloring (the 4-color-theorem is a deliberate red herring here). Affix pools are weighted-mix (color-tilted, nonzero on everything), with a **hard Gold×Purple exclusion** (no node carries both XP and vision/sensor mods).

**Application to node modifiers:** a node's color-type is an intrinsic property (`node_type: enum {R, G, B, W}`), not a stat. Stats like `strength`, `dexterity`, `intelligence` are what scale that type's attacks. A Red node typically carries `+STR` modifiers, reinforcing the melee identity — but a Red node with an unusual `+INT` modifier is a valid designer choice that creates interesting tension. Dual-color interior nodes (e.g. R/B) are high-value precisely because they may let an attacker choose the favorable side of the triangle per strike (timing of that choice is an open combat question).

---

## Open Questions

1. **Editor plugin**: how early to invest? The `StringName` stat_id works without a plugin, just less safe. A minimal plugin that validates stat_id against the registry on save would be high value for low cost.

2. **Growth formula for XP**: `ExpStat.grow()` currently does `_max.base_value = _max.value * 1.25 + 10`. This is gameplay logic inside a stat class. In v2 this should be a `Callable` or a separate `GrowthCurve` resource on `PoolStatDefinition`. Keeps stats dumb.

3. **`IncrementalStatModifier`** (the multiplier-based one): currently modifies `stat._multiplier` directly, bypassing the normal pipeline. Needs to be folded into the standard operation enum cleanly.

4. **Fog of war / vision_range on TreeNode**: unrelated to stats but currently exported there. Probably should move to a separate component.

5. **Multiplayer**: `StatsManager` has commented-out RPC sync code. If multiplayer comes back, the `RuntimeStat` + signal approach supports it cleanly — sync the modifier list, not the computed value.

6. **Node addon stacking**: can multiple addons of the same type be applied to one node? Needs design decision before architecture commitment.

7. **Core aura falloff**: linear, exponential, or step-function (shell)? Affects how "core position matters" as a tactical choice. Worth prototyping all three — and the combat doc's core classes (radius / shell / distance-loving) depend on this being parameterizable.

8. **`resist_r/g/b` vs. flat `armor`**: does the game want a full type-resist system or is flat armor + the node type triangle sufficient? The combat doc leans on `resist_*` as the *primary* home of the triangle (emergent, respec-able). Risk to watch: early-game, before resists are allocated, the triangle may feel absent — a tiny hardcoded baseline multiplier could backstop it.

9. **Movement points as a pool vs. a scalar reset**: are `movement_speed` and `deallocation_points` pools (current/max, reset to max each turn) or scalars the systems read and track externally? Pool is architecturally cleaner (same pattern as health/SP). Scalar is simpler if they never change mid-turn.

10. **Per-node health modeling**: full `RuntimePoolStat` per node (signals + clamping for free) vs. a lightweight field on the node's combat component. Leaning `RuntimePoolStat`, seeded per-node from entity totals + addons. (See Per-Node Health.)

11. **`crit_mult` as the lone FLOAT board stat**: keep it FLOAT, or express crit as an INT percentage bonus to damage to keep the board uniformly INT? Affects the "all stats are small INTs" cleanliness goal.
