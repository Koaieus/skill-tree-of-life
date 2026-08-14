# Audit — `systems/` (13 files, 2738 lines)

Read in full: all 13 `.gd` in `systems/`, `scenes/game_root.tscn` (the DI wiring),
`.claude/rules/turn-manager.md`, `graph.md`, `click-grammar.md`, `entity-death.md`,
`gdscript-pitfalls.md`, `skill-node-addons.md`, `docs/design/click_grammar.md`,
`docs/domain/allocation_system.md`, `loot-system.md`, `vision-system.md`, plus
`gh issue view 404/411 --comments`.

## Preamble — three direct answers to the brief

**1. The input rework is not pending; it shipped.** #411 closed 2026-08-09
(the grammar doc), #404 closed 2026-08-12 (the implementation). The code audited
today **is** the post-#404 model: one `_pop_armed_mode()` primitive shared by
right-click and Esc, both routed through `_unhandled_input` (global, not
node-scoped), with nesting expressed as array order in `_armed_modes`. Current
structure will not fight the change — it is the change. The live follow-ups are
**#338** (a "Move Core" tray button, which collapses `_route_core_move_click`'s
self-click-cancel branch into the generic invalid-target pop) and **#412**
(armed-mode vignette). Nothing in `systems/` blocks either.

**2. Right-click: was three behaviours, is now two, and the design doc calls the
survivor vestigial.** Post-#404 there is exactly one grammar path
(`_pop_armed_mode`, `player_input_controller.gd:225`) plus the idle pin-toggle
fallback (`:227-229`). Melee/magic setup-step and ranged clear-selection have all
collapsed into `AttackPlan.pop()` overrides (`melee_attack_plan.gd:83`,
`ranged_attack_plan.gd:29`, `magic_attack_plan.gd:35`), dispatched via the base
`_on_node_right_clicked` (`attack/plan/attack_plan.gd:63`). The pin-toggle is the
one residual meaning, and `docs/design/click_grammar.md` ("Out of scope") already
flags it as a debug-era leftover slated for hover+`I`. So: not scattered across
files any more — one handler, one primitive, three `ArmedMode` levels.

**3. BattleSystem is two responsibilities, not three.** `launch_attack`'s
resolve → VFX-await → AP-deduction is one coherent commit sequence and splitting
it buys nothing. But `_on_node_depleted` + `_cascade_layers` is a genuinely
separate axis: it is triggered by `Events.skill_node_depleted`, has **no
relationship to the active plan** (it runs correctly with `attack_plan == null`,
from any damage source including a corpse's own cascade), and performs
defender-side ownership accounting (`wound`, `dealloc_damage`) that is
AllocationSystem's subject matter. See finding 3.

**Ordering coupling (LootSystem):** the *phase* ordering is **explicit** and
sound — `Entity.die()` emits `entity_dying` then `entity_died` as two synchronous
phases (`entity/entity.gd:406-407`), documented in `entity-death.md`,
`loot_system.gd:5-11`, and the loot doc; it is immune to tree order by
construction. The *implicit* couplings sit next to it: killer attribution
(finding 8) and the ledger-clear (finding 9).

---

### 1. LARGE | systems/allocation_system.gd:96 | Scene-authored ownership never applies node modifiers
**Defect:** `register_scene_authored_ownership()` performs `allocation_level = 1`, `claim(1)` and `_grant_node_effects` but omits `node.apply_entity_modifiers_to(board)`, which both `allocate()` (:156) and `force_allocate()` (:190) call, and no other code path calls it (only 2 non-test call sites exist repo-wide).
**Breaks:** every hand-authored owned node's `modifiers` array is silently inert today — `scenes/dev_sandbox.tscn`'s `Right` (`mod_str_2`) and `Down` (`mod_hp_5` + one more) are owned by Player in the scene and grant the player nothing, so the sandbox's stat baseline diverges from an identical procgen-spawned board.
**Fix:** add `n.apply_entity_modifiers_to(n.owned_by.stat_board)` to the loop, and pin it with a test asserting a scene-owned node's modifier reaches the owner's board.

### 2. LARGE | systems/allocation_system.gd:202,242 | Teardown duplicated across deallocate/force_deallocate
**Defect:** `deallocate` and `force_deallocate` each re-implement the identical five-step teardown (`clear_scaled_effect_sets` → `_revoke_node_effects` → `remove_entity_modifiers_from` → `mirror_remove` → `owned_by = null` → `dispatch`), diverging only in accounting and which signal fires — while the *setup* pair is a documented deliberate non-composition, and `register_scene_authored_ownership` is a third setup path that re-lists the side-effects again.
**Breaks:** `docs/domain/allocation_system.md` claims the side-effect set is "exposed as the `force_allocate` primitive", but it is re-implemented three times; #376's `clear_scaled_effect_sets` already had to be inserted into both teardowns, and the next such step needs the same double-edit with no compiler help when one is missed (finding 1 is exactly that failure, on the setup side).
**Fix:** extract one private `_strip(node, previous) -> void` teardown atom that both public methods call, then have `register_scene_authored_ownership` call `force_allocate`-minus-`claim` rather than re-listing steps.

### 3. LARGE | systems/battle_system.gd:226 | Cascade authority is a second system inside BattleSystem
**Defect:** `_on_node_depleted` + `_cascade_layers` (78 lines) reacts to a global bus signal, never reads `attack_plan`, and applies defender-side ownership accounting (`force_deallocate` + `skill_points.wound` + `health.deplete`) that duplicates AllocationSystem's subject matter — it is co-located with the attack authority only by history.
**Breaks:** the invariant "wound and chip-damage accompany every forced dealloc" lives in a file whose other 220 lines are about the attacker's plan lifecycle, so a second forced-dealloc caller (concede, a hazard, a spell that strips territory without depleting HP) silently skips it; `deallocate_all_owned` on death already bypasses it entirely.
**Fix:** move the cascade into its own `CascadeSystem` node (or onto AllocationSystem beside `force_deallocate`) with a `graph`/`allocation_system` NodePath pair, leaving BattleSystem owning the plan and its launch sequence.

### 4. MEDIUM | systems/allocation_system.gd:489,498 | can_allocate is O(N+E) per call, and the overlay calls it per node
**Defect:** `_has_any_owned_node` walks `graph.get_skill_nodes()` and `_is_adjacent_to_owned` walks `graph.get_edges()` — both accessors that *rebuild a fresh typed array per call* (`.claude/rules/graph.md`) — and `ManagerHighlightProvider.get_node_role` calls `can_allocate` from `node_highlight_overlay.gd:65`'s loop over every node.
**Breaks:** repainting manage-mode highlights is O(N·(N+E)) and re-fires on every allocate/deallocate/force-dealloc and every SP change (`highlight_controller.gd:74-76,133`) — the exact shape `graph.md` records as having already shipped once as a real bug (13.9 ms per allocation at 41 owned nodes), now at 500–2500 nodes.
**Fix:** hoist both to entity-owned state — `_has_any_owned_node` is `entity.navigator.get_mirrored_nodes().is_empty()`, and adjacency should read the cached `graph.get_neighbours(node)` index instead of a full edge walk.

### 5. MEDIUM | systems/player_input_controller.gd:274 | Denial feedback paints the player's islanding for anyone's denial
**Defect:** `_on_node_action_denied` is subscribed to the global `Events.node_action_denied` and unconditionally computes `player.navigator.nodes_islanded_by_removing(node, player.core_location)` regardless of which entity's action was denied.
**Breaks:** any future NPC/AI or second-player denial pulses the *human player's* islanded subgraph danger-red around an enemy node — feedback that is not merely cosmetic noise but actively misinforms about the player's own topology; it also puts VFX-driving code in the input router.
**Fix:** add an `entity` argument to `Events.node_action_denied` (or filter on `node.owned_by == player`) and move the pulse/shake into a presentation listener.

### 6. MEDIUM | systems/player_input_controller.gd:582 | AP/mana gates read `.current`, not `available()`
**Defect:** `can_player_act()` gates on `ap.current <= 0` and `battle_system.gd:155,161` gate on `ap_pool.current` / `mana_pool.current`, while `.claude/rules/stats-system.md:144` states the rule ("gates and budgets must read `available()`") and explicitly names `PlayerInputController` and `HighlightController` as compliant examples.
**Breaks:** latent today only because `action_points`/`mana` are plain `PoolStat` in `entity/default_entity_board.tres` (`available() == roundi(current)`); the moment either becomes a `SurplusPoolStat` — as `deallocation_points` and `movement_points` already are in that same file — the gate denies cells the player can actually spend, and the rule file is currently lying about which files comply.
**Fix:** switch all three reads to `available()` and correct the rule doc's compliance list.

### 7. MEDIUM | systems/allocation_system.gd:276-347 | Staking verbs have no production caller
**Defect:** `can_stake` / `stake` / `can_extract` / `extract` (~90 lines, plus `STAKE_CEILING` and `_core_within_one_hop`) are called only from `test/unit/test_staking.gd` — no UI, no input channel, no AI reaches them.
**Breaks:** the #337 economy (SP staked-bucket transfers, AP cost, DP refund, displaced-fill refund) is unreachable in the running game while its downstream consumers — `allocate`'s refill branch (:166-169), the cascade's `maxi(fill, 1)` wound multiplier — are live and shape balance off a cap nothing can raise.
**Fix:** either wire the input channel (tray verb, per the #338 shape) or mark the block explicitly as pre-wired-for-#337 in a comment so the next reader does not assume it is exercised.

### 8. MEDIUM | systems/loot_system.gd:185 | Killer attribution is structurally unenforced
**Defect:** `_resolve_killer` reads `turn_manager.current_entity` and is correct only because death fires synchronously inside the attacker's `launch_attack` call stack — a comment-documented invariant with no assertion, no source threading, and no test that would fail if it broke.
**Breaks:** the system's own docstring (:32-34) and `docs/domain/loot-system.md` both name thorns/counter-damage as the case that inverts it — a defender-turn kill would pay XP and the spell draft to the *victim's killer's victim*, silently; the `killer != victim` guard catches only the self-kill.
**Fix:** thread the damage source through `DamageInstance` → `entity_dying`, or at minimum add an `assert` plus a test that pins the current-entity assumption so a future counter-damage path fails loudly.

### 9. MEDIUM | systems/loot_system.gd:163-165 | Removal ledger never clears without a BattleSystem
**Defect:** `_removed_this_attack` is cleared only by `_on_attack_launched`, which is connected only inside `if battle_system != null`; `_on_cascade_started` is likewise gated, but the ledger is *read* unconditionally by `_award_kill_xp` (:208).
**Breaks:** in any composition where `battle_system` is unset (the doc calls this the "headless fixtures" path, and `@export` makes it a one-inspector-slip configuration) entries accumulate across attacks and turns, so the kill bonus counts territory removed by earlier attacks at bonus rate — the exact double-pay the attack-scoping was introduced to prevent.
**Fix:** clear the ledger in `_on_entity_dying` after the payout as well, so scope is bounded regardless of which signals are wired.

### 10. MEDIUM | systems/player_input_controller.gd:486 | Group lookup where an exported dep belongs, and it is a cycle
**Defect:** `_set_drag_preview_target` resolves `HighlightController` via `get_tree().get_first_node_in_group(...)` per drag frame instead of an `@export`ed NodePath (`.claude/rules/scene-composition.md`), and then reaches into the controller's active provider to push state into it.
**Breaks:** `HighlightController` already holds `@export var input_ctl` pointing back here (`highlight_controller.gd:31`), so the two systems are mutually coupled with only one direction declared in `game_root.tscn` — a reader of the scene cannot see that input drives highlights, and the per-frame group scan is invisible to the DI graph.
**Fix:** delete the push; expose the snapped landing as a read on `PlayerInputController` (like `move_targeting_source()`) and let `HighlightController`, which already has the NodePath, pull it when building the core provider.

### 11. MEDIUM | systems/player_input_controller.gd:498-534 | Drag-badge presentation composed in code in the input router
**Defect:** `_ensure_core_drag_visuals` / `_clear_core_drag` build a `Label.new()` with a runtime font-size override, z_index, world offset and `"%d hop%s · %d MP left"` text formatting, and free it by hand — 40 lines of presentation inside a systems-layer input router. (The ghost itself is correctly a `CorePresence` scene instance; the badge and all the styling are not.)
**Breaks:** the drag affordance cannot be restyled, themed, or previewed in the editor, and it duplicates the "float a readout near the cursor" job that `ui/` already owns — #412's armed-mode HUD affordance will have to either fight this or reproduce it.
**Fix:** package ghost + badge as one `core_drag_ghost.tscn` with a `bind(hops, mp_left, landing)` method, preloaded and instanced here; the router keeps only the snap math.

### 12. MEDIUM | systems/turn_manager.gd:36 | Turn ownership is closed by an outside write, past end_turn()
**Defect:** `GameRoot._on_entity_died` writes `turn_manager.current_entity = null` directly (`scenes/game_root.gd:166-167`) because TurnManager itself has no death awareness, and `start_turn`'s `assert(current_entity == null)` — the only thing guarding the invariant — is compiled out in release builds.
**Breaks:** the death path skips `turn_ended.emit()` entirely, so every `turn_ended` subscriber (`PlayerInputController._emit_gate_changed`, `:112`) misses the transition when the acting entity dies on its own turn; and in a release build a genuine double-`start_turn` overwrites the current entity with no error at all.
**Fix:** have TurnManager subscribe to `Events.entity_died` and route through a real `end_turn()`-equivalent that emits `turn_ended`, and replace the release-erased assert with a `push_error` + early return.

### 13. MEDIUM | systems/armed_mode.gd:11 | ArmedMode subclasses reach into the controller's privates
**Defect:** all three subclasses hold a `PlayerInputController` back-reference and read/write its underscore members (`_ctl._temp_upgrade_arm`, `_ctl._set_temp_upgrade_arm`, `_ctl._move_targeting_source`, `_ctl._active_attack_plan()`), and `_route_battle_click` likewise calls `plan._on_node_left_clicked` / `_on_node_right_clicked` from outside.
**Breaks:** the abstraction claims to be a level of a stack but owns no state — it is a callback pair bound to another object's privates, so adding a fourth level (#338's Move Core arm) means adding a fourth private on the controller and a fourth reacher, and the underscore convention no longer signals anything.
**Fix:** either move the arm state onto its `ArmedMode` (the mode owns its own level, the controller owns only the ordered list), or drop the classes for three `Callable` pairs — the indirection currently costs three files and buys no encapsulation.

### 14. MEDIUM | systems/player_input_controller.gd:571 | Armed plan becomes unpoppable when the AP gate closes
**Defect:** `AttackPlanArmedMode.is_armed()` returns `_ctl.can_player_act() and ...`, so a plan that is still set becomes invisible to `_has_armed_mode()` / `_pop_armed_mode()` the moment AP hits 0 or `is_launching` goes true.
**Breaks:** in that window right-click silently falls through to the pin-toggle, Esc opens the PauseMenu, and `_update_cursor` resets to `CURSOR_ARROW` while the plan is still live and still claiming left-clicks — latent today only because the AP-spending verbs reachable while armed are limited (finding 7 keeps `stake` unreachable), which is not a property anyone maintains deliberately.
**Fix:** make `is_armed()` a pure state read (`_ctl._active_attack_plan() != null`) and keep `can_player_act()` where it belongs — on the push (left-click) path, not the pop.

### 15. MEDIUM | docs/domain/allocation_system.md:—— | Domain docs drifted from the code they describe
**Defect:** the allocation doc's Signals section is wrong on both entries (`allocated` is 3-arg with a `forced` flag since the VFX split; `deallocated` does **not** fire from the forced path — `force_deallocated` does) and the doc has zero mention of staking, ~90 lines of live API; `docs/domain/loot-system.md` says the per-node trickle "rides `Events.skill_node_destroyed`" when the code rides `battle_system.cascade_started`; `docs/domain/vision-system.md` calls `SkillNode.get_local_stat` where the code is `get_local_value`.
**Breaks:** these are the four documents the brief itself hands a new agent as the way in, and the signal claim in particular would send someone to subscribe to `deallocated` for shatter VFX — the precise mistake the two-signal split exists to prevent.
**Fix:** correct the three files against the code in one pass; the allocation doc additionally needs a staking section or an explicit "staking is #337, see the code" pointer.

### 16. NIT | systems/vision_system.gd:219 | Local-stat rebind is unguarded and skipped when viewers empty
**Defect:** `_rebind_local_stats` connects without the `is_connected` guard its sibling `_bind_entity_stat` uses, and it is called only inside `_recompute`'s non-empty-viewers branch — so switching to zero effective viewers leaves every previously-bound node stat still connected to `_request_recompute`.
**Breaks:** stale subscriptions keep waking a system that has nothing to compute, and the missing guard makes any future second call site an "already connected" error rather than a no-op.
**Fix:** mirror `_bind_entity_stat`'s guard and move the disconnect sweep above the empty/non-empty branch.

### 17. NIT | systems/allocation_system.gd:427 | `_real_neighbours` hand-rolls an edge walk the cache already serves
**Defect:** it iterates `graph.get_edges()` to find neighbours, which `.claude/rules/graph.md` names explicitly ("Don't hand-roll an edge walk" — `get_neighbours()` reads a cached adjacency index and is O(degree)).
**Breaks:** every `can_move_core` call is O(E) instead of O(degree), and the hand-rolled copy will not pick up future adjacency-index fixes.
**Fix:** `graph.get_neighbours(node)` then filter `n != node` to preserve the self-loop exclusion this version does deliberately.

### 18. NIT | systems/battle_system.gd:26 | 21 bare `Dictionary`/`Array` — two of them are cross-system contracts
**Defect:** 21 untyped collections live in this slice (vision 13, loot 5, alloc 2, battle 2, highlight 1); most are locals, but two are public contracts: `signal cascade_started(layers: Array, defender: Entity)` — whose consumer must cast, `loot_system.gd:240` `for n in (layer as Array)` — and `AllocationSystem.reachable_core_landings() -> Dictionary` (`SkillNode → int`), consumed by two callers that each re-annotate.
**Breaks:** the cast in LootSystem is the compiler's job done by hand, and a wrong-shaped `layers` payload would surface as a runtime cast failure inside the reward system rather than at the emit site.
**Fix:** type the two contracts (`Array[Array]` and `Dictionary[SkillNode, int]`); leave the locals unless touched.

### 19. NIT | systems/loot_system.gd:385 | `_attach_addon` wrapper adds nothing
**Defect:** `func _attach_addon(node, addon) -> void: node.add_child(addon)` — one call site, no logic, and `.claude/rules/skill-node-addons.md` states plainly that attaching *is* `add_child` and warns against second entry points.
**Breaks:** it implies an attach protocol exists, which is the exact misconception the rule file was written to kill.
**Fix:** inline the `add_child` call.

### 20. NIT | systems/player_input_controller.gd:67 | Temp-upgrade arm is `Variant` end to end
**Defect:** `_temp_upgrade_arm`, `arm_temp_upgrade`, `temp_upgrade_arm()` and `signal temp_upgrade_arm_changed(upgrade: Variant)` are all untyped, and the code then does `_temp_upgrade_arm.script` (:174) with no type to guarantee the member.
**Breaks:** the tray, the plan's `toggle_temp_upgrade`, and this controller pass a `MeleeAttackPlan.TEMP_UPGRADE_CATALOG` entry with zero compile-time agreement on its shape; a catalog entry missing `script` fails at runtime inside the denial-reason branch.
**Fix:** give the catalog entry a named type (a small `Resource` or `RefCounted` class) and thread it through instead of `Variant`.

## Verdict

The slice is well-modelled where it has been revisited recently and drifts where it
has not: the input layer is genuinely at the #404/#411 design (one pop primitive,
one handler, nesting as list order), and the two-phase death bus is a textbook fix
for a real ordering hazard. The load-bearing weakness is `AllocationSystem`, which
is the codebase's central verb and has three setup paths and two teardown paths
re-listing the same side-effect set by hand — a duplication that has already
produced one live bug (scene-authored modifiers never applied) and will produce
the next one the same way. `BattleSystem` carries a second, plan-independent
system (the cascade) that belongs beside `force_deallocate`, and `systems/` is
where per-node cost gets multiplied by 2500, so the `can_allocate` walk reached
from a per-node overlay loop is the one performance finding worth acting on. The
domain docs meant to onboard the next reader are wrong in specifics that would
actively mislead.
