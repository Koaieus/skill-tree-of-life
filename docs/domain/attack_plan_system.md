# Attack-plan system — current state, decisions, pickup notes

Engineering-side architecture doc for the in-turn attack flow. The
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
  and the virtual surface: `validate()`, `get_node_role(node)`,
  `_on_node_left_clicked(node)`, `_on_node_right_clicked(node) -> bool`,
  `pop() -> bool`, `get_node_range(node)`. Concrete plans override what
  they care about and emit `state_changed` on any internal mutation.
  Click grammar (left arms/resolves, right pops one level, self-targeting
  falls through to a pop when invalid) is `docs/design/click_grammar.md`
  — `pop()` is the one primitive shared by right-click and the
  self-targeting fallthrough.
- **`HighlightRole`** enum on `AttackPlan` — `NONE`, `ORIGIN`, `MEMBER`,
  `HOSTILE_TARGET`, `FRIENDLY_TARGET`, `IN_RANGE`, `INVALID`. Semantic,
  not literal — `ORIGIN` covers melee pivot, magic source, and ranged
  firing position.
- **`Targeting`** (abstract `Resource`) — encapsulates "what counts as a
  valid target." Abstract `is_valid_target(plan, source, candidate)`;
  default `valid_targets()` iterates the live graph and filters via the
  predicate (enough for NODE-kind subclasses). `TargetingKind` enum on
  the base (`NODE`/`EDGE`/`POSITION`/`SELF`) for future input dispatch.
  Concrete: `NodeTargeting`, with an `ownership_filter` flag mask
  (`Neutral`/`Mine`/`Ally`/`Hostile`/…) rather than one subclass per
  ownership shape.
- **`RangeFinder`** (abstract `Resource`) — single method
  `in_range(plan, source, candidate)`. Composed by Targeting subclasses.
  Concrete: `EuclideanRangeFinder` (max_distance), `HopRangeFinder`
  (max_hops via the global Navigator's AStar).
- **`SpellDef`** — Resource holding name / description / mana_cost /
  damage / `targeting: Targeting`. Spell instances live as `.tres` files
  under `attack/spell/defs/`. First spell: `spark.tres` — 5 damage, 1 mana,
  hostile-node targeting + 3-hop range.

### Mode plans

- **`MeleeAttackPlan`** — left-click sets the pivot (when unset), then
  left-click toggles blade members (cap = `attacker.stat_board.blade_size`,
  base 1 + `floor(STR/10)`). Right-click pops the pivot and every member
  with it — re-pivoting is pop-then-push, not a direct reassign. Embeds a
  `GraphMirror` of `{pivot} ∪ blade_nodes`; deselecting a member runs
  `nodes_islanded_by_removing(node, pivot)` *before* the removal, then
  cascade-prunes anything islanded from the pivot. Mirror is freed via
  `NOTIFICATION_PREDELETE` (Node base, plan is RefCounted).
- **`RangedAttackPlan`** — left-click an enemy node to set the target
  (left-click a different hostile node to retarget directly — no origin
  step to pop first). Right-click pops the target. Firing positions are
  derived from `attacker.navigator.get_leaf_nodes()`; leaves within
  `FIRING_RANGE` (280px) of the target light up as `ORIGIN`.
  `get_node_range()` returns `FIRING_RANGE` for leaves so the overlay
  paints a faint reach circle that brightens when active.
- **`MagicAttackPlan`** — left-click an owned node to set the source
  (when unset), then left-click any node within reach (per spell
  targeting) to set the target. Right-click pops the source and target
  together — re-sourcing is pop-then-push. Auto-equips `spark.tres` at
  plan creation since the spell picker UI isn't built yet.

### Plumbing

- **`SkillNode`** emits `left_clicked(self)` and `right_clicked(self)`
  separately (split from one `clicked` signal). Also carries per-node
  combat HP — see Combat resolution below.
- **`PlayerInputController`** routes both clicks by **input channel** —
  there are no turn phases. When it's the player's turn and an attack
  plan owned by the player is active (a mode was chosen in the
  `AttackModeBar`), it dispatches to the plan's virtual click handler;
  otherwise the click falls through to the core-move and then the
  allocate channels (a bare left-click on an unowned node allocates).
- **`BattleSystem`** rebinds `attack_plan.state_changed` across plan
  swaps and re-emits as `attack_plan_state_changed`. UI subscribes once
  to the system, not per plan. Also owns `launch_attack()` (the commit
  flow) and the forced-dealloc cascade — see Combat resolution.
- **`AttackHighlightOverlay`** (`Node2D` mounted under `Graph` by
  `GameRoot`) — subscribes to both BattleSystem signals,
  `queue_redraw()`s on either, paints role rings + range circles. One
  overlay, every plan type.

### Combat resolution

The plans plan; this layer commits.

- **`AttackOutcome`** (RefCounted) — what `plan.resolve()` returns:
  `hits: Array[DamageInstance]` + `ap_cost: int`. Used twice:
  preview-on-hover (future tooltip UI) and commit-on-launch.
- **`DamageInstance`** — `amount` + `type` (PHYSICAL / MAGIC / TRUE) +
  `source` (the plan or spell) + `target` (the SkillNode being hit) +
  `origin` (firing position, for VFX routing).
- **`attack/formulas/`** — pure-function damage modules. One per
  offense profile (`RangedDamageFormula` is the only one wired so far:
  `floor(DEX / 10) + 1` PHYSICAL per shot), one for the universal
  defense step (`Mitigation.apply` — pass-through stub today). Plans
  use the offensive helpers; `SkillNode.take_damage` calls the
  defensive one. The boundary lands at the moment damage arrives.
- **`AttackPlan.resolve() -> AttackOutcome`** — abstract; called for
  *both* preview and commit. Implementations are pure: no state
  mutation on plan, attacker, world. `RangedAttackPlan.resolve()`
  loops `get_reaching_firing_positions()` and produces one
  `DamageInstance` per shot. Melee and magic ship as empty-outcome
  stubs awaiting their per-mode follow-ups.
- **`BattleSystem.launch_attack()`** — three-phase coordinator:
  1. `plan.resolve()` (pure)
  2. `await attack_vfx.play_ranged_volley(outcome)` (animates, applies
     damage on each tracer's arrival)
  3. AP deduction + `_reset()` (cleared before the await window so the
     player can't spam-click during VFX)
- **`Events.skill_node_damaged(node, amount, source)`** /
  **`Events.skill_node_depleted(node)`** — global signals re-emitted
  by `SkillNode.take_damage`. The damage signal is what makes the
  damage-numbers widget mode-agnostic; the depleted signal is what
  BattleSystem listens for to run the cascade.
- **`SkillNode.current_hp` / `take_damage()` / `refill()`** — per-node
  combat HP. Plain field, not in the modifier pipeline (see
  `docs/domain/node-hp.md`). Core nodes never deallocate; overflow
  past `current_hp` routes to `owned_by.stat_board.health`.
- **`AllocationSystem.force_deallocate(node)`** — bypasses the
  voluntary `can_deallocate` guards (is_core, DP cost, would_disconnect)
  and emits `deallocated` but does *not* refund SP. The caller (which
  is always `BattleSystem._on_node_depleted`) does the wound + core HP
  loss instead. This is the "elsewhere" the file's top comment
  foretold.
- **`BattleSystem._on_node_depleted(node)`** — the cascade. Snapshots
  `defender.navigator.nodes_islanded_by_removing(node, core)` BEFORE
  touching the mirror; force-deallocs each node in the cascade
  (depleted node + all newly islanded), each costing the defender
  `skill_points.wound(1)` and `health.deplete(1)`.

### Turn-start upkeep

Lives on `Entity._on_turn_started` (the explicit "no god-mode
TurnManager" pattern). Per-turn bookkeeping consumes:

- `action_points` → `restore_to_full()`
- `deallocation_points` → `restore_to_full()`
- `xp` → `+xp_per_turn`
- `skill_points.heal(wound_heal_per_turn)` — `wound_heal_per_turn` is
  the new ScalarStat for this (default 1)
- `SkillNode.refill()` on every owned node (via
  `EntityNavigator.get_mirrored_nodes()` — new GraphMirror query)

### VFX layer

- **`AttackVFX`** (Node2D, sibling of `AttackHighlightOverlay` under
  `Graph`) — `play_ranged_volley(outcome) -> void` (coroutine).
  Spawns one `RangedTracer` per `DamageInstance`, staggered 60ms; each
  tracer applies its own hit's damage on arrival; the coroutine
  resumes when the last tracer arrives.
- **`RangedTracer`** — code-only Node2D. Quadratic Bezier (start →
  start + (0, -200) apex → target), ~0.55s flight, custom-drawn glow
  + position trail. Emits `arrived` then linger-then-`queue_free`.
- **`DamageNumberLayer`** — Node2D global subscriber to
  `Events.skill_node_damaged`. Spawns a private `_DamageFloater`
  (custom-drawn `draw_string` + outline) at the node's position;
  tweens up + fade. Completely decoupled from attack source — any
  future damage (spells, traps, status effects) gets floating numbers
  for free.
- **Hit flash** — lives on the SkillNode itself, listening to its own
  local `damaged` signal. Tweens `Visuals.modulate` red → white.

### Launch UI

- **`LaunchAttackButton`** (own scene + .gd + .gdshader). UIRoot gates
  enabled iff `plan != null and plan.is_valid()`; pressed calls
  `battle_system.launch_attack`. Procedural fire shader when active,
  desaturated when disabled. Same `ColorRect + Label + ShaderMaterial`
  pipeline as `AttackModeButton`.
- **`EndTurnButton`** (own scene + .gd + .gdshader). Promoted from a
  plain Button inline in `ui_root.tscn`. Same pipeline. Phases are gone,
  so its label is a static "End Turn" (no per-phase text flips). When
  ending the turn would waste `action_points` **and** an enemy node is
  visible, UIRoot (`_unspent_warning` / `_any_enemy_visible`) calls
  `show_confirm()` with the warning, popping an inline confirmation
  bubble instead of ending; clicking the bubble — or ctrl-clicking the
  button — commits the turn. No visible enemy means no AP-costing action
  is left, so unspent AP raises no warning.

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

- **`blade_size`** ScalarStat, intrinsic DerivedStatModifier:
  `ADD_BASE floor(STR/10)`. Base value 1 → default total is
  `1 + floor(STR/10) = 2` at STR=10.
- **`wound_heal_per_turn`** ScalarStat, base 1 — the rate that wounds
  flow back to spendable SP at turn start. Tuning lever for
  combat-recovery cadence.

### Sandbox

`scenes/dev_sandbox.tscn` has a Red Player (inline stat board) and a
Blue Enemy (`default_entity_board.tres`) bridged by unallocated nodes.
Both boards include `wound_heal_per_turn`. Enough geometry for ranged
firing positions to actually have things to fire at, and the Enemy
having a board means damage flow has something to deplete on commit.

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
- Targeting types are reusable across modes — a `NodeTargeting` with
  `ownership_filter = Hostile` serves ranged-target and magic-target equally.
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

Matches the existing `Def` suffix convention (`StatDef`, `StatModifier`,
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

### Combat resolution: three-phase commit (resolve → VFX → apply)

`BattleSystem.launch_attack` separates:
1. **Pure resolution** (`plan.resolve()`): no side effects; pure
   `(plan state) → AttackOutcome`. Same call used for preview.
2. **Animation** (`await attack_vfx.play_ranged_volley(outcome)`):
   tracers spawn, fly, apply damage per arrival.
3. **State mutation** (AP deduction + plan reset).

Considered alternatives:

- **Fire-and-forget VFX, apply immediately, animate later**: clean to
  write but visually wrong — numbers would pop before tracers land.
  And per-shot stagger needs the apply step to ride the arrival
  signal, not a single pre-await batch.
- **Plan.commit(ctx) that does everything**: tighter coupling, but
  plans then need to know about VFX dispatch + AP cost + cascade
  routing. Keeping `resolve` pure means the *same* method drives the
  damage-tooltip preview that ships later; no second code path.

### Offense per-plan, defense per-target

Each plan's `resolve()` builds raw `DamageInstance`s using helpers in
`attack/formulas/` (offense profile per attack mode).
`SkillNode.take_damage()` calls `Mitigation.apply(raw, defender_board)`
*before* deducting `current_hp`. Reason:

- Mode-specific damage (DEX-per-shot vs STR-per-contact vs INT-per-cast)
  has fundamentally different shape; trying to unify it in one
  resolver kills the cleanliness.
- Mitigation is universal: armour, resists, magic shields apply
  regardless of who's shooting. Putting it on the defender means one
  pipeline, every source.
- The boundary lands at the moment damage *arrives*. Attacker says
  "5 PHYSICAL"; defender's node says "I have 1 armour, take 4."
  Cleanest possible split.

### Per-shot damage instances (vs consolidated total)

`RangedAttackPlan.resolve()` emits one `DamageInstance` per firing
position, not one consolidated total. Reasons:

- **Flat armour reads correctly.** N hits × small damage, each reduced
  by armour, is meaningfully different from one big hit reduced once.
  Locks in armour as a viable defensive stat shape.
- **VFX staggers naturally.** Tracers can arrive 60ms apart, each
  applying its own hit, producing separated impact moments — the
  AttackVFX layer doesn't need to invent staggered damage.
- **AoE / multi-shot uniformity.** The same shape covers a single
  spark (one hit), a volley (N hits), a fireball (one origin, many
  targets), an AoE radial (many origins, many targets). One data
  type, every attack.

### Cascade lives on BattleSystem, not AllocationSystem

The forced-dealloc cascade (depleted node + islanded nodes → dealloc
+ wound + core HP) lives on `BattleSystem._on_node_depleted`, a
subscriber to `Events.skill_node_depleted`. AllocationSystem grew a
`force_deallocate(node)` helper but doesn't subscribe to the signal.
Reason:

- AllocationSystem is the voluntary-allocation rules engine. Forced
  dealloc by attack is a *combat outcome*. Wound + core HP routing is
  combat policy, not allocation policy.
- Coupling AllocationSystem to combat would invert dependency:
  combat-system-changes would touch the allocation files. Keeping the
  cascade on BattleSystem means combat changes stay in combat code.
- The Events bus carries the depleted signal because *anything* may
  cause a node to die — direct combat, area-effect spells, future
  status DoT. One subscriber, all damage sources.

### Node HP is a plain field, not a Stat

`SkillNode.current_hp` is a bare float; `get_max_hp()` reads
`owner.stat_board.node_health`. Not a `PoolStat`, not in the modifier
pipeline. Full reasoning in `docs/domain/node-hp.md`. TL;DR: cross-board
derivation (node-local + owner stats) isn't a supported pattern yet
and node-local stats don't exist; building infrastructure for absent
state would be premature. Clean seam: the entire concern lives at
`get_max_hp()` and `_refresh_hp_binding`. When node-local stats land,
those two methods graduate to a real cross-board derivation.

### Damage numbers via `Events.skill_node_damaged`, not direct VFX calls

`DamageNumberLayer` subscribes to the global signal; it does *not*
take callbacks from BattleSystem or AttackVFX. Reasons:

- A spell, a falling trap, a thorn aura, a future status-effect DoT —
  none of them need to know "there's a floating-number widget I
  should call." They call `node.take_damage(amount, source)` and the
  number appears.
- Adding a second damage-number style (crit yellow, healing green) is
  a single subscriber change, no source coordination.
- Mode-specific UI (e.g. a "Magic" tinting if `source is SpellDef`) is
  one branch in the subscriber, not N branches at every emit site.

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

### Mitigation stats — armour + resistances (small)

**Prereq:** none — the seam already exists. **Touches:** new
StatBoard fields (`armour`, maybe per-type resistances), update
`Mitigation.apply()` to actually subtract / multiply, possibly add a
`damage_type` mapping for per-type resistance.

Right now `Mitigation.apply` returns `raw.amount` unchanged. The
single function is the entire defense pipeline; growing it is one
edit + one set of stat definitions. Decide whether resistances are
PoE-style additive % or D&D-style per-source flat — design call.

### Melee `resolve()` (medium, depends on phantom-swing sandbox)

**Prereq:** the existing phantom-swing sandbox graduates to a real
attack (defines the contact set: which enemy nodes a blade sweep
actually hits). **Touches:** `MeleeAttackPlan.resolve()`,
`attack/formulas/melee_damage.gd` (new), maybe `AttackVFX.play_melee_swing`.

The empty-outcome stub is the placeholder. Damage formula likely
`floor(STR / 10) + 1` PHYSICAL per contact, mirroring ranged's per-shot
shape. Per-contact instances let armour bite each one independently —
keeps the offense/defense symmetry the ranged path established.

### Magic `resolve()` + spell effect payload (medium)

**Prereq:** spell effect data shape — `SpellDef` currently has `damage:
int` as a placeholder. **Touches:** `MagicAttackPlan.resolve()`,
`attack/formulas/magic_damage.gd` (new), possibly grow `SpellDef` to
carry an effect kind enum (damage / heal / debuff / status).

The Spark proof-of-concept (one target, damage by INT//10) lands first.
AoE spells require Targeting `valid_targets()` returning multiple +
one DamageInstance per resolved target. Status effects need a
container on the outcome (`effects: Array[StatusInstance]` alongside
`hits`).

### Damage / death preview overlay (small, depends on hover hook)

**Prereq:** plan.resolve is pure — already true. **Touches:** new
overlay widget + maybe a hover-target hook in plans.

When hovering a candidate target with a plan active:

- Show projected damage on the target (and any AoE collaterals) — call
  `plan.resolve()` and read `outcome.hits`.
- Show projected deaths (per-target damage vs `node.current_hp`).
- Show projected island cascade from those deaths (via
  `defender.navigator.nodes_islanded_by_removing_set(projected_kills,
  defender_core)`).

Probably a separate overlay (above the highlight overlay) that listens
to `Events.skill_node_hovered` + `attack_plan_state_changed`. Could
add a `PROJECTED_KILL` role; could also keep it in its own visual
vocabulary entirely. Lean: keep it separate so the highlight role enum
stays minimal.

### Forced-dealloc cascade visual feedback (small, depends on AttackVFX seam)

When a damaged node dies and cascade-disallocates kin, the player needs
to *see it*. Hooks off the existing `AllocationSystem.deallocated`
signal — already emits for the cascade nodes. Wire a `DeallocFlash`
layer (same pattern as `DamageNumberLayer`: global subscriber, custom
draw). Could share VFX helpers with `AttackVFX`.

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

**Prereq:** none — combat resolution is in. **Touches:** new
`EnemyController` that builds AttackPlans for non-player entities on
their turn.

The plan abstraction is AI-friendly: AI builds the same plan types the
player does, calls `plan.resolve()` to score (it's pure!), picks the
highest-EV plan, calls `battle_system.launch_attack`. A
`MinimaxAttackPlanner` could score plans by damage dealt × territory
captured / mana spent. MVP: random valid plan, just to test the cycle.

---

## File index

```
attack/
├── plan/
│   ├── attack_plan.gd            # abstract base — state_changed, role enum, virtuals, resolve()
│   ├── melee_attack_plan.gd      # pivot + blades + cascade-prune (resolve stub)
│   ├── ranged_attack_plan.gd     # target + firing positions, resolve() per-shot
│   └── magic_attack_plan.gd      # source + spell + target (resolve stub)
├── outcome/
│   ├── attack_outcome.gd         # hits[] + ap_cost
│   └── damage_instance.gd        # amount, type, source, target, origin
├── formulas/
│   ├── ranged_damage.gd          # pure: (attacker, firing, target) → DamageInstance
│   └── mitigation.gd             # pure: (raw, defender_board) → effective amount
├── range_finder/                 # in_range primitives (Euclidean, hop)
├── targeting/                    # is_valid_target predicates + kind
├── spells/
│   └── spark.tres                # first spell
├── spell_def.gd                  # name, cost, damage, targeting
graph/
└── graph_mirror.gd               # abstract; +get_mirrored_nodes for turn-start sweeps
skill_node/
└── skill_node.gd                 # +current_hp, take_damage, refill, damaged/depleted
entity/
├── entity.gd                     # _on_turn_started: AP/DP, XP, wound heal, node refill
└── stats/
    ├── stat_board.gd             # +wound_heal_per_turn
    └── list/wound_heal_per_turn.tres
ui/
├── attack_highlight_overlay/     # role rings + range circles
├── attack_vfx/
│   ├── attack_vfx.gd             # play_ranged_volley coroutine
│   └── ranged_tracer.gd          # Bezier-arc projectile, custom-drawn
├── damage_number_layer/
│   └── damage_number_layer.gd    # global Events.skill_node_damaged subscriber
├── launch_attack_button/         # .gd + .tscn + .gdshader (fire)
└── end_turn_button/              # .gd + .tscn + .gdshader (vortex)
autoload/
└── events.gd                     # +skill_node_damaged, +skill_node_depleted
systems/
├── battle_system.gd              # plan owner; launch_attack; cascade
├── allocation_system.gd          # +force_deallocate (no SP refund)
└── player_input_controller.gd    # click dispatch
docs/domain/
├── attack_plan_system.md         # this file
└── node-hp.md                    # why per-node HP isn't (yet) in the stat pipeline
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
