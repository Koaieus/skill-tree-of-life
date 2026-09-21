@tool
extends Node

#region World facts — emitted by the owner of the fact, after it is true; a listener may not mutate the world in response (that is a system's job through a named entry)

## Re-emitted by SkillNode.take_damage so UI (floating damage numbers, screen
## shake, etc.) can subscribe once globally instead of binding to every node.
signal skill_node_damaged(node: SkillNode, amount: float, source: HitInstance)

## Re-emitted by SkillNode.heal_damage and SkillNode.refill (non-silent) so UI
## can show heal numbers. amount is the effective HP delta (always > 0).
signal skill_node_healed(node: SkillNode, amount: float, source: HitInstance)

## Emitted when a non-core node's current_hp reaches 0. BattleSystem listens,
## announces the VFX layers and forwards into [method EntityCombat.apply_cascade].
##
## [param source] is the [HitInstance] that did it, or null for an unattributed
## deplete (a test, a scripted kill). It is here so the cascade can be RECORDED
## back onto the hit that caused it (#518): the handler is synchronous, so by
## the time `emit` returns, `source.deallocations` holds what leaving cost the
## defender. Without it a hit could report damage totals but not the attrition
## vector — and a node left at 1 HP versus a node killed are entirely different
## moves to an AI.
signal skill_node_depleted(node: SkillNode, source: HitInstance)

## Re-emission of [signal SkillPointStat.wounds_applied] / [signal SkillPointStat.wounds_healed]
## keyed by the owning entity. Entity itself does the re-emit so the global
## bus carries the entity reference (a stat doesn't know its owner). UI floater
## layers subscribe here instead of binding to every entity's SP stat.
signal entity_wounded(entity: Entity, amount: int)
signal entity_healed(entity: Entity, amount: int)

## An entity gained XP — kill rewards, the per-turn WIS income, anything that
## calls `xp.replenish`. Re-emitted by Entity off [signal PoolStat.replenished_by]
## for the same reason as the wound/heal pair above: the stat doesn't know its
## owner, and a UI layer shouldn't have to bind per-entity. `amount` is the XP
## asked for, not the amount that fit under the cap — a fill carries its excess
## into the next level, so the honest number to show the player is the grant.
signal entity_xp_gained(entity: Entity, amount: float)

## A stat modifier became visible on an entity (#70/#79). A PURE domain fact —
## no presentation: `binding` is how the modifier is held ([enum
## ModifierBinding.Kind]), `added` is gained-vs-lost. The [FloaterDirector]
## translates this into a floater; nothing about colour/shape lives on the bus.
##
## Deliberately separate from the logical "modifier applied" (StatBoard.add_modifier,
## which fires ~11×/spawn for intrinsics + class mods and for the whole death strip).
## Emitted from gameplay call sites at the visual moment — immediately for
## non-travelling sources (SkillDust pickup, voluntary dealloc), and on pulse
## arrival for allocation.
signal stat_modifier_changed(entity: Entity, modifier: StatModifier, binding: ModifierBinding.Kind, added: bool)

## Two-phase death announcement (see Entity.die), so consumers pick a phase
## instead of racing on connection order. emit() is synchronous, so EVERY
## `entity_dying` handler finishes before ANY `entity_died` handler runs —
## ordering is by phase, not by tree position.
##
## `entity_dying` — PRE-cleanup: the corpse still owns its nodes / subgraph.
## Readers that must snapshot the live world subscribe here (LootSystem's loot
## draw + kill XP). Killer attribution is NOT carried on either signal —
## LootSystem resolves it from its injected TurnManager, keeping Entity dumb.
signal entity_dying(entity: Entity)
## `entity_died` — CLEANUP phase: AllocationSystem strips the corpse's owned
## nodes, GameRoot handles the player-vs-NPC consequence (game-over / despawn).
## GameRoot rides the child-before-parent ready order to fire after
## AllocationSystem, so the despawn never races the node strip.
signal entity_died(entity: Entity)

## A defender's spike popped an incoming enemy blade vertex (#170) — the hostile
## vertex died on contact (and severed whatever it dragged off the handle). Fired
## from the live swing at the contact moment. [param defender] is the spiked node
## that popped it, [param attacker] whose blade it was, [param position] the
## contact point. VFX hooks listen to play the pop burst; a future spike-reload
## system (#189) can count charges off this without touching the detection.
signal blade_vertex_popped(defender: SkillNode, attacker: Entity, position: Vector2)

## The run reached a terminal state (#460). [VictorySystem] is the SOLE emitter
## and fires this at most once per run, carrying the populated [RunOutcome].
## The outcome is point-of-view-free (#517): it names the winning camp and
## nothing else. "Did *I* lose" is a fact about a MACHINE, not about the run, so
## [HudRoot] resolves it at display time from the local [SeatPolicy].
signal run_ended(outcome: RunOutcome)

## Sparse status-tick channel (#879). Re-emitted by [method TurnManager.start_turn]
## for a REAL turn begin only — never [method TurnManager.adopt_turn]'s resync
## cursor (#756's `is_adopting`) — and only AFTER [signal TurnManager.turn_started]'s
## own emit has returned, so every listener of that signal (including
## [method Entity._on_turn_started]'s upkeep / [method SkillNode.apply_turn_regen])
## has already run. A [SkillNode] with ≥ 1 status connects to this once (on its
## first status) and disconnects on its last, checks `entity == owned_by`, then
## calls [method NodeCombat.tick_statuses] — never a territory sweep. Distinct
## from [signal TurnManager.turn_started] on purpose: that one's seven listeners
## (HUD, initiative bar, action cluster, …) all want to hear an adopted cursor
## too; this one exists so a status tick never has to.
signal turn_started(entity: Entity)

## A scout landing revealed [param node]'s surroundings to [param viewer]'s
## vision group: emitted by [method RevealInstance.land_on] on the LIVE world
## only (a shadow land is a no-op — the preview shows no disc), so a peer
## hears it from its own rebuilt [AttackRecord]. [param radius] is world
## units. [VisionSystem] is the one consumer: it owns the resulting mark, its
## per-viewer decay through `effects/status/scouted.tres`, and its circle.
signal node_scouted(node: SkillNode, viewer: Entity, radius: float)
#endregion

#region UI feedback — presentation-only; nothing under systems/ or command/ connects here (revisit-when: it does)

signal skill_node_hovered(node: SkillNode)
signal skill_node_unhovered

## Floating-tooltip signals for SpellPickerButton hover. [SpellTooltip]
## subscribes to both; the button emits on mouse_entered / mouse_exited.
## [param caster] is the player entity whose stats may modify spell values.
signal spell_hovered(spell: SpellDef, caster: Entity)
signal spell_unhovered

## Fired by GraphCamera (`scenes/camera_2d.gd`) whenever a zoom step lands —
## the tween's TARGET, not a per-frame mid-tween value. Edge listens so its
## line width can hold constant screen-pixel coverage (#399) without every
## edge polling the camera in `_process`.
signal camera_zoom_changed(zoom: float)

## A node-targeted verb was denied by its own gate (DP/SP/AP, non-islanding,
## etc.) — PURE fact, no presentation baggage: node + a short reason string.
## Any verb can fire this on gate failure, not just deallocate (#404). Consumers
## decide what "denied" looks like (PlayerInputController's blink+shake today).
signal node_action_denied(node: SkillNode, reason: String)

## A HUD-widget-targeted verb was denied (#743's spell-picker mana gate is the
## first case) — the [signal node_action_denied] sibling for a refusal that
## has no [SkillNode] to anchor at and is not fog-gated (a HUD button is always
## visible to the machine showing it). [param anchor] is a Node2D the toast can
## place at directly — typically a widget's own `%FloatAnchor` marker — never a
## world node. [FloaterDirector] renders both through the same
## `_denial_text()` / `_DENIAL_TEXTS` table; see its docstring.
signal ui_action_denied(anchor: Node2D, reason: String)

## Fired by [AIController] on every AI decision this turn (growth allocation,
## attack pick, or "nothing sensible") — ALWAYS, regardless of the
## controller's local `debug_trace` toggle. No production listener yet;
## `test_ai_controller.gd` / `test_ai_controller_combat.gd` connect to pin
## the unconditional-emit contract. This is the seam a future HUD overlay /
## DebugClipboard fan subscribes to without touching the controller (#378).
## `entity` is the deciding AI, `summary` a short human-readable description
## of the decision.
signal ai_decision(entity: Entity, summary: String)

## #504: the death is now visible — [method Entity.die] is the sole emitter and
## fires this LAST, after both bus phases above, so the corpse's nodes are
## already stripped when GameRoot despawns it. Under design B the model dies at
## the moment it is drawn dying, so this is no longer a "the reveal caught up"
## gate; it is the ordering seam that keeps despawn behind cleanup. Kept
## separate from `entity_died` for exactly that reason — see GameRoot's
## `_on_entity_death_shown`.
signal entity_death_shown(entity: Entity)
#endregion

#region World→UI requests — a system asks the HUD for a decision; the answer comes back through a command, never a return value

## Emitted when a claimed SkillDust relic offers a node-mod pick-N-from-M choice
## (#173). Carries a [LootPickRequest]; a UI consumer sets `handled = true`
## SYNCHRONOUSLY to take over the pick, otherwise the emitter auto-resolves a
## random pick — so NPCs and headless tests never need a listener. Only the
## human player's relics reach a picker (the HUD filters on `request.collector`).
signal loot_pick_requested(request: LootPickRequest)

## Emitted when a killing blow drafts a spell off the victim's permanent
## (core) spellbook (#204). Carries a [SpellLootRequest]; a UI consumer sets
## `handled = true` SYNCHRONOUSLY to take over the pick, otherwise the emitter
## (LootSystem) auto-resolves a random pick — so NPCs and headless tests never
## need a listener. Only the human player's drafts reach a picker (the HUD
## filters on `request.collector`).
signal spell_loot_requested(request: SpellLootRequest)
#endregion
