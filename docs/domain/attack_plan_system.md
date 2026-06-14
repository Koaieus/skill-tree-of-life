# Attack-plan system — current state, decisions, pickup notes

Engineering-side architecture doc for the battle-phase attack flow. The
game-design view of attacks (damage formulas, color triangle, dismemberment,
etc.) lives in `docs/design/combat_system.md`; this doc covers the *code
shape* the design rides on.

Session-handoff format: what's in, the decisions behind it (with the
alternatives we ruled out so we don't relitigate), and the queue for the
next session — enough that a fresh Claude session can pick up without
re-deriving anything.

---

## What's in

### Cross-mode primitives

- **`AttackPlan`** (abstract `RefCounted`) — base for every mode. Owns
  `attacker`, `mode`, `signal state_changed`, the `HighlightRole` enum,
  and the virtual surface: `validate()`, `get_highlight_role(node)`,
  `_on_node_left_clicked(node)`, `_on_node_right_clicked(node)`,
  `get_node_range(node)`. Concrete plans override what they care about
  and emit `state_changed` on any internal mutation.
- **`HighlightRole`** enum on `AttackPlan` — `NONE`, `ORIGIN`, `MEMBER`,
  `HOSTILE_TARGET`, `FRIENDLY_TARGET`, `IN_RANGE`, `INVALID`. Semantic,
  not literal — `ORIGIN` covers melee pivot, magic source, and ranged
  firing position.
- **`Targeting`** (abstract `Resource`) — encapsulates "what counts as a
  valid target." Abstract `is_valid_target(plan, source, candidate)`;
  default `valid_targets()` iterates the live graph and filters via the
  predicate (enough for NODE-kind subclasses). `TargetingKind` enum on
  the base (`NODE`/`EDGE`/`POSITION`/`SELF`) for future input dispatch.
  Concrete: `SingleHostileNodeTargeting`, `SingleAlliedNodeTargeting`.
- **`RangeFinder`** (abstract `Resource`) — single method
  `in_range(plan, source, candidate)`. Composed by Targeting subclasses.
  Concrete: `EuclideanRangeFinder` (max_distance), `HopRangeFinder`
  (max_hops via the global Navigator's AStar).
- **`SpellDef`** — Resource holding name / description / mana_cost /
  damage / `targeting: Targeting`. Spell instances live as `.tres` files
  under `attack/spells/`. First spell: `spark.tres` — 5 damage, 1 mana,
  hostile-node targeting + 3-hop range.

### Mode plans

- **`MeleeAttackPlan`** — right-click pivot, left-click blade members
  (cap = `attacker.stat_board.blade_size`, base 1 + `floor(STR/10)`).
  Embeds a `GraphMirror` of `{pivot} ∪ blade_nodes`; deselecting a
  member runs `nodes_islanded_by_removing(node, pivot)` *before* the
  removal, then cascade-prunes anything islanded from the pivot.
  Re-pivoting clears the blade. Mirror is freed via
  `NOTIFICATION_PREDELETE` (Node base, plan is RefCounted).
- **`RangedAttackPlan`** — left-click an enemy node to set the target,
  right-click the target to clear it. Firing positions are derived from
  `attacker.navigator.get_leaf_nodes()`; leaves within `FIRING_RANGE`
  (280px) of the target light up as `ORIGIN`. `get_node_range()` returns
  `FIRING_RANGE` for leaves so the overlay paints a faint reach circle
  that brightens when active.
- **`MagicAttackPlan`** — right-click an owned node to set the source,
  left-click any node within reach (per spell targeting) to set the
  target. Re-sourcing invalidates the target if it now falls out of
  reach. Auto-equips `spark.tres` at plan creation since the spell
  picker UI isn't built yet.

### Plumbing

- **`SkillNode`** emits `left_clicked(self)` and `right_clicked(self)`
  separately (split from one `clicked` signal).
- **`PlayerInputController`** routes both clicks. In battle phase with an
  active plan owned by the player, dispatches to the plan's virtual
  click handler; otherwise falls through to allocation routing
  (deployment phase).
- **`BattleSystem`** rebinds `attack_plan.state_changed` across plan
  swaps and re-emits as `attack_plan_state_changed`. UI subscribes once
  to the system, not per plan.
- **`AttackHighlightOverlay`** (`Node2D` mounted under `Graph` by
  `GameRoot`) — subscribes to both BattleSystem signals,
  `queue_redraw()`s on either, paints role rings + range circles. One
  overlay, every plan type.

### Graph layer (foundation)

- **`GraphMirror`** abstract base — `astar`, `_node_ids`, idempotent
  `mirror_add`/`mirror_remove`, `wire_to(graph)` contract with
  overridable `_should_mirror`, full query surface
  (`get_nodes_by_degree`, `get_leaf_nodes`, `connected_component`,
  `nodes_islanded_by_removing(_set)`, `would_disconnect_from`).
- **`Navigator`** — auto-wires, mirrors everything.
- **`EntityNavigator`** — auto-wires, `_should_mirror = owned_by == entity`.
  AllocationSystem drives ownership flips by calling `mirror_add`/
  `mirror_remove` directly.
- **`BladeMirror`** (logical name; instantiated as a plain `GraphMirror`
  inside `MeleeAttackPlan`) — manual sync, no graph subscriptions.

### Stats

- **`blade_size`** ScalarStat, intrinsic DerivedModifierDef:
  `ADD_BASE floor(STR/10)`. Base value 1 → default total is
  `1 + floor(STR/10) = 2` at STR=10.

### Sandbox

`scenes/dev_sandbox.tscn` has a Red Player (full stat board) and a Blue
Enemy (no board, just a colour and a 5-node territory) bridged by
unallocated nodes. Enough geometry for ranged firing positions to
actually have things to fire at.

---

## Decisions made — alternatives ruled out

### `HighlightRole` is semantic, not literal

We almost called the enum members `PIVOT`/`BLADE`/`FIRING_POSITION`/
`MAGIC_SOURCE`/`TARGET`. We didn't, because:

- The overlay shouldn't care *which mode* a node belongs to, only what
  *role* it plays in the active plan.
- Pivot, magic source, and firing position all answer the same question
  ("where does the attack emanate from?") — that's one role.
- Per-mode visuals can still differ — the overlay can branch on
  `plan.mode` for theming without polluting the role enum.

Symmetric **`HOSTILE_TARGET`** + **`FRIENDLY_TARGET`** rather than one
`TARGET` plus ownership-derivation: keeps the role pure semantic, lets
heals and damage spells be distinguished without the overlay re-checking
`owned_by`.

### BladeMirror is a plan-owned `GraphMirror`, not a third subclass

Original proposal was a third `GraphMirror` subclass (`BladeMirror`).
Settled on instantiating the base class directly because:

- The base already has all the queries and mirror ops we need.
- The blade has *no* auto-sync — it's purely plan-driven via
  `mirror_add` / `mirror_remove`. A subclass with no overrides is dead
  weight.
- `GraphMirror` extends `Node`, so the plan (RefCounted) frees it via
  `NOTIFICATION_PREDELETE`. The mirror never enters the scene tree.

Ruled out: refactoring `GraphMirror` to `RefCounted` so plans could hold
it without manual cleanup. The cost (Navigator/EntityNavigator becoming
Node wrappers around a composed mirror, every existing caller migrating
to `navigator.mirror.X`) wasn't worth the marginal lifecycle win.

### Deselect cascade auto-prunes (vs disallow)

When deselecting a blade member would island other members from the
pivot, we *drop the islanded members too* rather than disallowing the
deselect. Reason: more fluent UX — the player just gets a smaller blade
instead of a wall. Implementation falls out of `nodes_islanded_by_removing`
(which was needed anyway for the forced-dealloc damage cascade).

### Targeting is a composable Resource, not a SpellDef polymorphism

Original sketch had `Spell` subclasses encoding targeting + effect
together. Settled on `SpellDef + targeting: Targeting` because:

- Targeting is orthogonal to effect. Fireball and Frostbolt share
  "single enemy node within range R" — they differ only in damage type.
  Subclassing SpellDef per spell duplicates targeting logic.
- Targeting types are reusable across modes — a `SingleHostileNodeTargeting`
  serves ranged-target and magic-target equally.
- `Targeting` is small and easy to subclass for new shapes (EDGE,
  POSITION, AoE) without touching SpellDef.

For the `TargetingKind` axis (NODE vs EDGE vs POSITION vs SELF) we chose
**enum + virtual `get_kind()`** rather than polymorphic Targeting
subclasses with explicit kind types. Reason: the kind is metadata for
input dispatch, not the behaviour itself. Default of `NODE` covers most
cases; subclasses override only when different.

### `RangeFinder` is separate from `Targeting`

Could have inlined a `max_range: float` on each Targeting (initial
version did this). Pulled it out into `RangeFinder` because:

- Reach models multiply quickly — Euclidean, graph hops, owned-territory
  hops, line-of-sight, hop-via-edge-type, etc. Inlining all of them
  into Targeting subclasses combinatorially explodes.
- A spell wants a *targeting* (what kind of node) × a *reach* (how to
  measure distance) — these are independent axes. Composition wins.
- AI / preview overlays may want to ask "is X in range of Y?" without
  caring about Targeting at all. Standalone primitive serves both.

### SpellDef rename (from `Spell`)

Matches the existing `Def` suffix convention (`StatDef`, `StatModifierDef`,
`PoolStatDef`). `Spell` reads like a runtime instance ("cast a spell");
`SpellDef` reads like authored data ("the Spark spell definition"). The
distinction will matter when spells gain runtime state (charges,
cooldown timers, instance modifiers).

### Plan→UI via direct signals, not the `Events` bus

`Events` autoload stays minimal (currently just `skill_node_hovered`/
`unhovered`). Plan/spell state flows BattleSystem → UI via direct
signals because:

- Plan has a single lifetime owner (BattleSystem). UI binds via the
  system; the system rebinds across plan swaps. No "which plan emitted
  this?" filtering at the consumer.
- Bus signals erase context — consumers end up cross-checking against
  `battle_system.attack_plan` anyway. Direct rebinding is the same
  work, more obvious shape.
- The bus stays for genuinely many-to-many ambient events (hover,
  future `skill_node_long_pressed` etc.).

### `_on_node_*_clicked` virtuals on plans, not event-bus dispatch

PlayerInputController dispatches into the active plan via virtual
methods rather than emitting an `attack_node_clicked` bus signal that
the plan listens to. Reason: type-safe, locally-scoped (one plan
active at a time), trivially testable, and lets plans no-op the click
types they don't care about (no `match` on event type per plan).

### `get_node_range` hook on `AttackPlan` (vs overlay branches)

Overlay paints range circles by asking the plan
`get_node_range(node) -> float`. Default returns 0 (no circle); ranged
plan returns `FIRING_RANGE` for leaves. Considered:

- **Overlay type-checks the plan** (`if plan is RangedAttackPlan: ...`)
  — breaks the closed-overlay-open-plan polymorphism.
- **Range-customization struct** returned by the plan (Color + radius +
  alpha) — premature; one float + role-derived color is enough.

If a future plan wants multiple radii per node (e.g. melee's blade arc
+ ranged firing reach simultaneously), we'll generalize then.

### MagicAttackPlan auto-equips the default spell

`_init()` preloads `spark.tres` and sets `spell = _DEFAULT_SPELL`. This
is a stopgap so magic mode does *something* before the spell-picker UI
exists. Replace with picker-driven assignment when the UI lands.

### Hop counting uses the global Navigator

`HopRangeFinder` walks `plan.attacker.navigator.graph.navigator.astar`
— the global Navigator, mirrors all nodes. So a spark cast from a
player-owned source can route its hop-counting *through* enemy
territory. That matches the design intent: the spark travels through
the graph regardless of who owns the nodes along the way.

Future: an "owned-territory hops" range finder would use
`attacker.navigator.astar` (EntityNavigator). Different reach model,
different RangeFinder subclass. Pattern is set up for it.

---

## Queue for the next session

Roughly in dependency order. Each entry has the rough size, the
prerequisites, and the design intent so we don't rederive.

### Combat resolution — actually apply damage (medium)

**Prereq:** none. **Touches:** new `CombatSystem` node + per-node HP
tracking (already a `node_health` board stat; per-node HP is on the
design doc but not coded).

The plans currently *plan* attacks; nothing fires. Need:

- A "Commit" button (or click trigger) that asks `plan.is_valid()` and
  then enacts it. Likely an `AttackResolver` / `CombatSystem` that takes
  a validated plan, computes per-target damage, applies it.
- Per-`SkillNode` HP: a `current_health` field (transient — not a board
  stat). When it hits 0, forced deallocation → cascade.
- The cascade reuses `EntityNavigator.nodes_islanded_by_removing_set`
  (set-variant deliberately exists for this).
- AP/MP deduction on commit. AP from `attacker.stat_board.action_points`.
- Animation / VFX hooks live with the resolver, not the plan.

### Damage / death preview overlay (medium, depends on Combat resolution)

**Prereq:** Combat resolution shapes the damage call. **Touches:** new
overlay widget + plan hooks.

When hovering a candidate target with a spell selected:

- Show projected damage on the target (and any AoE collaterals).
- Show projected deaths (HP would drop ≤ 0).
- Show projected island cascade from those deaths (via
  `defender.navigator.nodes_islanded_by_removing_set(projected_kills,
  defender_core)`).

Probably a separate overlay (above the highlight overlay) that listens
to `Events.skill_node_hovered`. Could add a `PROJECTED_KILL` role; could
also keep it in its own visual vocabulary entirely. Lean: keep it
separate so the highlight role enum stays minimal.

### AttackPlanPanel sub-widgets (small, no prereq)

**Prereq:** none. **Touches:** new UI widget(s) under the existing
`AttackModeBar` / a sibling panel.

Per-mode HUD:

- Melee: blade count `(X / max_blades)`, max_blades reading live from
  the stat board.
- Magic: spell name + mana cost + damage; later, spell picker.
- Ranged: firing-position count `(reaching / total)`.

Listens to `attack_plan_changed` (to mount the right sub-widget) and
`attack_plan_state_changed` (to re-read state). UIRoot composes it.

### Spell picker UI (small, depends on AttackPlanPanel)

Removes the `_DEFAULT_SPELL` preload stopgap. Magic mode's sub-widget
shows the player's known spells (`attacker.spells` — not yet a field,
add one) and lets the player click to equip. `MagicAttackPlan.spell`
setter clears `target` if it falls out of reach under the new spell.

### Forced-dealloc cascade visual feedback (small, depends on Combat resolution)

When a damaged node dies and cascade-disallocates kin, the player needs
to *see it* — a deallocate flash + a brief "X nodes lost to islanding"
toast. Hooks off the existing `AllocationSystem.deallocated` signal.

### blade_target — what is it? (small design decision)

`MeleeAttackPlan.blade_target: Vector2` is a placeholder from the
original sketch. The blade is a connected node set, but the *sweep*
direction / arc origin needs definition. Options:

- A Vector2 (e.g. mouse position at commit) — defines the arc center
  for animations.
- An enemy-side target node — defines whose territory the blade
  "lashes out toward."
- Nothing — the blade just applies to all its members on commit; no
  directional element.

Design decision pending. Probably defer until melee animation lands.

### More RangeFinder subclasses (small, on-demand)

- `OwnedHopRangeFinder` — same as `HopRangeFinder` but routes through
  `attacker.navigator.astar` (owned territory only).
- `LineOfSightRangeFinder` — Euclidean within reach + no obstructing
  topology (TBD what "obstructing" means).
- `EdgeWalkRangeFinder` — for spells that traverse edges as chains.

### More Targeting subclasses (small, on-demand)

- `AoEHostileNodeTargeting` — area effect; `valid_targets` returns
  *all* nodes within reach of source instead of just one.
- `EdgeTargeting` — for spells that target an edge.
- `PositionTargeting` — for ground-target spells; consumes
  `_on_world_clicked(Vector2)` instead of node clicks. PlayerInputController
  needs a world-click handler for this.

### Enemy AI (large)

**Prereq:** Combat resolution exists. **Touches:** new `EnemyController`
that builds AttackPlans for non-player entities on their turn.

The plan abstraction is AI-friendly: AI builds the same plan types the
player does, asks `validate()` and `valid_targets()`, picks one, commits.
A `MinimaxAttackPlanner` could score plans by damage dealt × territory
captured / mana spent. MVP: random valid plan, just to test the cycle.

---

## File index

```
attack/
├── plan/
│   ├── attack_plan.gd            # abstract base — state_changed, role enum, virtuals
│   ├── melee_attack_plan.gd      # pivot + blades + cascade-prune
│   ├── ranged_attack_plan.gd     # target + firing positions
│   └── magic_attack_plan.gd      # source + spell + target
├── range_finder/
│   ├── range_finder.gd           # abstract — in_range(plan, source, candidate)
│   ├── euclidean_range_finder.gd
│   └── hop_range_finder.gd       # via global Navigator AStar
├── targeting/
│   ├── targeting.gd              # abstract — is_valid_target, valid_targets, kind
│   ├── single_hostile_node_targeting.gd
│   └── single_allied_node_targeting.gd
├── spells/
│   └── spark.tres                # first spell
├── spell_def.gd                  # name, cost, damage, targeting
graph/
└── graph_mirror.gd               # abstract; Navigator + EntityNavigator subclass
ui/
└── attack_highlight_overlay/
    └── attack_highlight_overlay.gd   # role rings + range circles
systems/
├── battle_system.gd              # plan owner, state_changed rebinding
└── player_input_controller.gd    # click dispatch
.claude/rules/
├── stats-system.md               # stat system contract (keep current)
└── godot-workflow.md             # class cache + scene round-trip gotchas
```

## Pickup tips for the next session

- The `.claude/rules/godot-workflow.md` rule is load-bearing: when you
  rename a `class_name` or add a new one, the cache needs
  `godot --headless --editor --quit`, and you must `git diff scenes/`
  immediately after to catch silent scene mutation.
- `MeleeAttackPlan` is the most complete plan and the best model for
  how to use `GraphMirror` from a plan. Read its
  `_set_pivot` / `_deselect_blade` pair before touching the others.
- The Stats v2 rule (`.claude/rules/stats-system.md`) requires updating
  the intrinsic-scaling table on any new derived modifier — this is how
  `blade_size` landed. Don't skip it.
- `SkillNode.left_clicked` / `right_clicked` are the only input
  primitive plans consume. If you want world-click (for
  PositionTargeting), `PlayerInputController` will need a new entry
  point — none exists yet.
