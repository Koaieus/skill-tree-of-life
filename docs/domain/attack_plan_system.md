# Attack-plan system — code shape

Engineering-side architecture doc for the in-turn attack flow. The game-design
view of attacks (damage formulas, color triangle, dismemberment) lives in
`docs/design/combat_system.md`; this doc covers the *code shape* the design
rides on. Its sibling `attack-timeline.md` covers the *timing* model — which
world state each part of an attack reads, and at which clock. Decisions:
ADR 0011 (one timeline contract for every mode), ADR 0012 (every arrow renders
whatever it did), ADR 0034 (armed input is a statechart stack).

## Cross-mode primitives

- **`AttackPlan`** (abstract `RefCounted`, `attack/plan/attack_plan.gd`) — base
  for every mode. Owns `attacker`, `mode`, `signal state_changed`, the
  `HighlightRole` enum and the virtual surface: `validate()`,
  `resolve_against(world)`, `get_node_role(node)`, `get_node_range(node)`,
  `windup_anchors(outcome)`, `reset()`. Concrete plans add domain verbs only
  (melee `set_pivot` / `clear_pivot` / `toggle_member`, ranged and magic
  `set_target`) and emit `state_changed` on any internal mutation. A plan has no
  click grammar: what a click means lives in the `systems/armed/` levels
  (`MeleeMode` / `BladeMode`, `RangedMode` / `MagicMode` / `TargetMode`) — see
  `docs/domain/click-grammar.md`.
- **`HighlightRole`** — see `ui/highlight/highlight_provider.gd` for the
  members. Semantic, not literal: `ORIGIN` covers melee pivot, magic source and
  ranged firing position; `HOSTILE_TARGET` / `FRIENDLY_TARGET` are symmetric so
  heals and damage spells are told apart without the overlay re-checking
  `owned_by`. Per-mode looks come from `HighlightProvider.get_theme_key()`
  (`AttackPlan` maps `mode` to `&"melee"` / `&"ranged"` / `&"magic"`), which the
  overlay looks up in its `themes`; it never branches on `plan.mode`.
- **`Targeting`** (abstract `Resource`) — "what counts as a valid target":
  abstract `is_valid_target(plan, source, candidate)`; default `valid_targets()`
  iterates the live graph and filters via the predicate. `TargetingKind`
  (`NODE`/`EDGE`/`POSITION`/`SELF`) is metadata for input dispatch. Concrete:
  `NodeTargeting`, with an `ownership_filter` flag mask
  (`Neutral`/`Mine`/`Ally`/`Hostile`/...). Targeting is orthogonal to effect, so
  `SpellDef` composes a `targeting: Targeting` rather than subclassing per spell.
- **`RangeFinder`** (abstract `Resource`) — `in_range(plan, source, candidate)`,
  composed by Targeting. Reach is a separate axis from targeting. Concrete:
  `EuclideanRangeFinder` (max_distance), `HopRangeFinder` (max_hops over the
  global Navigator's AStar, so a hop count routes *through* enemy territory).
- **`SpellDef`** — Resource holding name / description / damage /
  `targeting`; instances are `.tres` files under `attack/spell/defs/`. The `Def`
  suffix matches `StatDef` / `PoolStatDef`: authored data, not a runtime instance.

## Mode plans

- **`MeleeAttackPlan`** — the pivot is set first, then blade members are toggled
  (cap = `attacker.stat_board.blade_size`, base 1 + `floor(STR/10)`). Clicking a
  node not directly adjacent to the blade set mass-selects: `_try_select_path`
  runs `attacker.navigator.shortest_path_to_any(node, {pivot} ∪ blade_nodes)`
  and pulls in the whole excursion as one atomic toggle, rejected outright if it
  overruns the shared budget. Right-click pops the pivot and every member with it
  (re-pivoting is pop-then-push). The plan embeds a plain `GraphMirror` of
  `{pivot} ∪ blade_nodes` (manual `mirror_add` / `mirror_remove`, freed in
  `NOTIFICATION_PREDELETE` since the plan is RefCounted). Deselecting a member
  runs `nodes_islanded_by_removing(node, pivot)` *before* the removal and
  cascade-prunes whatever islanded: the player gets a smaller blade, not a wall.
  Also carries the reform primitives below.
- **`RangedAttackPlan`** — left-click an enemy node sets the target (a different
  hostile node retargets directly); right-click pops it. Firing positions are
  derived from `attacker.navigator.get_leaf_nodes()`; a leaf whose per-node-board
  reach (`get_node_range`) covers the target lights up as `ORIGIN` and fires.
  Shots are ranked wave-major (`get_firing_schedule`), one `DamageInstance` per
  shot, so flat armour reads per hit and tracers can stagger.
- **`MagicAttackPlan`** — pick the spell in the tray (`SpellPickMode`,
  `ui/spell_picker_bar`), then left-click a target directly; the cast-from node
  is auto-picked and stamped in the same click (no source-selection step).
  Right-click pops target and source together. See `SpellTargetUnion`.
- **`SpellTargetUnion`** (`attack/targeting/spell_target_union.gd`) — the
  one shared answer to "what can this spell hit, from anywhere I own, and
  from where is each target best hit?" Unions every eligible caster's
  reach and returns `target -> auto-picked source` (max node-local
  `spell_damage`, lowest `stable_id` breaking the tie — an order-dependent
  pick would make host and client disagree about the launch command),
  plus the per-source reach and target sets the reach visual and
  `AiController` (#745) draw from.

  **The perf lever is the loop order, not the cache.** The obvious
  implementation calls `Targeting.valid_targets` once per source, and that
  sweeps all 800 nodes each time. Candidates come from the range finder
  first instead (`RangeFinder.gather_multi`: a bounded BFS per source for
  hops, ONE merged sweep for euclidean), and the ownership predicate runs
  only over those. The union then rides **its own** dirty flag —
  `state_changed` fires on every hover, so reusing it would re-walk the
  graph on mouse movement; `BattleSystem` pushes `invalidate_union()` on
  allocation and turn change instead.

  **Vision is the caller's.** The union answers reachability only.
  `MagicAttackPlan` filters highlights through the seat's `VisionSystem`;
  the AI keeps `AiRecon`. Baking one viewer's fog into a function the AI
  also calls would be wrong under `SeatPolicy` couch handover, where the
  acting entity is not the viewing seat.

## Plumbing

- **`SkillNode`** emits `left_clicked(self)`; right-click is the armed stack's
  pop (`ArmedStack`), not a node signal. It also carries per-node combat HP.
- **`PlayerInputController`** routes clicks by **input channel** — there are no
  turn phases — into the armed stack (`systems/armed/`), whose attack level owns
  the active plan; unclaimed clicks fall through to the core-move and allocate
  channels (a bare left-click on an unowned node allocates).
- **`BattleSystem`** rebinds `attack_plan.state_changed` across plan swaps and
  re-emits as `attack_plan_state_changed`; UI subscribes once to the system.
  It owns `launch_attack()` and the forced-dealloc cascade.
- **`NodeHighlightOverlay`** (`ui/node_highlight_overlay/`, mounted under
  `Graph` by `GameRoot`) paints role rings and range circles from the active
  plan; one overlay, every plan type, driven by `get_node_range(node) -> float`
  (default 0 = no circle).

## Combat resolution

- **`AttackOutcome`** (`attack/outcome/`) — what a plan resolves to: hits
  (`DamageInstance` / `HealInstance` / ...) plus `ap_cost`, replayed from the
  recorded `AttackRecord`. `DamageInstance` carries `amount`, `type`
  (PHYSICAL / MAGIC / TRUE), `source`, `target`, `origin` (firing position, for
  VFX routing) and `read_node` (the attacker-side node whose local stats the hit
  reads; resolve-local, never on the wire).
- **`AttackPlan.resolve_against(world)`** — abstract; all three plans implement
  it and land their outcome on the given `CombatWorld`, which is always a shadow
  (`resolve()` makes a throwaway one for previews and AI rollouts). See
  `docs/domain/attack-timeline.md`.
- **Launch** — `BattleSystem.launch_attack(plan)` submits a `LaunchAttackCommand`
  (`command/`); the resolved `AttackRecord` is replayed on the reveal clock
  through `CommandApplier`. See `docs/domain/attack-timeline.md`.
- **`attack/formulas/`** — offense profiles (`RangedDamageFormula`) and the
  universal defense step: `Mitigation.apply(raw, defender)` runs in
  `SkillNode.take_damage` at the moment damage arrives, reading `armor` and
  `min_damage_taken` node-locally. Offense is per-plan (DEX-per-shot vs
  STR-per-contact vs INT-per-cast have different shapes); mitigation is
  per-defender, one pipeline for every source.
- **`Events.skill_node_damaged(node, amount, source)`** /
  **`Events.skill_node_depleted(node)`** — re-emitted by `SkillNode.take_damage`.
  Damage numbers (`ui/floating_number_layer/`, `floater_*`) subscribe to the
  former so any damage source, present or future, gets a number for free;
  `BattleSystem` listens to the latter for the cascade.
- **`SkillNode.current_hp` / `take_damage()` / `refill()`** — per-node combat HP,
  a plain field outside the modifier pipeline (`docs/domain/node-hp.md`). Core
  nodes never deallocate; overflow past `current_hp` routes to
  `owned_by.stat_board.health`.
- **`AllocationSystem.force_deallocate(node)`** bypasses the voluntary
  `can_deallocate` guards (is_core, DP cost, would_disconnect) and emits
  `deallocated` without refunding SP.
- **`BattleSystem._on_node_depleted(node)`** — the cascade. It snapshots
  `defender.navigator.nodes_islanded_by_removing(node, core)` BEFORE touching the
  mirror, then force-deallocs the depleted node and each newly islanded one, each
  costing the defender `skill_points.wound(1)` and `health.deplete(1)`. The
  cascade lives on `BattleSystem`, not `AllocationSystem`: wound and core-HP
  routing is combat policy, and anything may deplete a node, so one subscriber
  to the bus signal covers every damage source.
- **Plan to UI via direct signals, not the `Events` bus.** A plan has a single
  lifetime owner (`BattleSystem`) and the system rebinds across plan swaps, so
  no consumer filters "which plan emitted this?". The bus is for genuinely
  many-to-many ambient events (hover, damage, depletion).

## Turn-start upkeep

Lives on `Entity.begin_turn` (no god-mode TurnManager): `action_points` and
`deallocation_points` restore to full, `xp` gains `xp_per_turn`,
`skill_points.heal(wound_heal_per_turn)` (ScalarStat, base 1), and
`SkillNode.refill()` runs on every owned node via
`EntityNavigator.get_mirrored_nodes()`.

## VFX and launch UI

- **`AttackVFX`** (under `Graph`) mounts a coordinator and plays an outcome:
  projectiles fly along `ui/vfx/projectile/path/` paths (e.g.
  `bezier_arc_path.gd`) and each hit applies on arrival.
- **Hit flash** lives on the SkillNode, listening to its own `damaged` signal.
- **`LaunchAttackButton`** (`ui/launch_attack_button/`) is enabled iff
  `plan != null and plan.is_valid()`; pressed calls `battle_system.launch_attack`.
- **`EndTurnButton`** (`ui/end_turn_button/`) has a static label. When ending
  the turn would waste `action_points` **and** an enemy node is visible,
  `action_cluster.gd` (`_unspent_warning` / `_any_enemy_visible`) calls
  `show_confirm()`; clicking the bubble, or ctrl-clicking the button, commits.
  No visible enemy means no AP-costing action is left, so no warning.

## Graph layer

- **`GraphMirror`** abstract base — `astar`, idempotent `mirror_add` /
  `mirror_remove`, `wire_to(graph)` with overridable `_should_mirror`, and the
  query surface (`get_nodes_by_degree`, `get_leaf_nodes`, `connected_component`,
  `nodes_islanded_by_removing(_set)`, `would_disconnect_from`).
- **`Navigator`** auto-wires and mirrors everything. **`EntityNavigator`**
  mirrors `owned_by == entity`; `AllocationSystem` drives ownership flips via
  `mirror_add` / `mirror_remove`. `GraphMirror` extends `Node`; the melee plan
  instantiates the base class directly instead of a third subclass.

## Stats

- **`blade_size`** — ScalarStat, base 1, intrinsic `ADD_BASE floor(STR/10)`.
- **`wound_heal_per_turn`** — ScalarStat, base 1: the rate wounds flow back to
  spendable SP at turn start.

## Reform last blade (#466)

The last **successfully launched** melee blade is remembered and
replayable.

- **Where the slot lives:** `PlayerInputController._reform_slots`, keyed by
  `Entity.get_instance_id()`, holding the plan's own `to_dict()` wire form. It
  is *client-local input state and never syncs* — reform is not a command, it
  expands into an ordinary `MeleeAttackPlan` that then launches through the
  normal path, so it adds no wire surface. Keyed per entity so a hot-seat
  handover can't let the incoming player reform the outgoing one's blade, and
  deliberately excluded from `clear_transient_state()`: the slot is the memory
  of a completed action, not half-finished intent, and it lasts the whole run.
- **Captured on `attack_launched`**, which fires inside `_commit` — i.e. only
  after `_resolve_for_launch` cleared the affordability gates. A refused launch
  therefore can never overwrite a good slot.
- **Availability is `MeleeAttackPlan.can_reform_selection()`**, a *pure*
  simulation of `_can_be_blade`'s ownership rule plus `_try_select_blade`'s
  budget and strict adjacency. It cannot be implemented by trial-reforming a
  scratch plan: rollback goes through `_clear_pivot()`, which frees
  `is_temporary` addons off the **real** SkillNodes.
- **Replay is strict and all-or-nothing** — `try_reform()` walks the stored
  (authoring) order through `_try_select_blade` only. **Never
  `_try_select_path`:** that is the click path's mass-select, and on a member
  that has drifted out of adjacency it silently pulls in a shortest path to
  reach it, reporting success with a *different, larger* blade. Accepted
  limitation: a blade constructible only in some other order is refused rather
  than reordered.
- **Restoring the swing direction writes `BattleSystem.next_melee_cw`**, not
  just `plan.swing_cw` — the tray's toggle label reads the sticky preference.
- Surfaced as the melee tray's Reform button and the `ui_reload` action (R — the armed level decides whether R means re-form or quiver reload, see `ArmedMode.reload`)
  (**R**). It rebuilds only; Launch stays the player's call. Temp upgrades are
  *not* restored (a second all-or-nothing gate sharing the same budget, which
  would need rollback semantics).

**No topology hash.** Availability replays the gates rather than hashing the
owned subgraph (a superset-tolerant digest is ill-defined): O(members) over
`Graph`'s cached adjacency index. `test_reform_still_works_after_territory_grows`
is the superset case.
