@tool
extends Node

signal skill_node_hovered(node: SkillNode)
signal skill_node_unhovered

## Re-emitted by SkillNode.take_damage so UI (floating damage numbers, screen
## shake, etc.) can subscribe once globally instead of binding to every node.
signal skill_node_damaged(node: SkillNode, amount: float, source: Variant)

## Re-emitted by SkillNode.heal_damage and SkillNode.refill (non-silent) so UI
## can show heal numbers. amount is the effective HP delta (always > 0).
signal skill_node_healed(node: SkillNode, amount: float, source: Variant)

## Emitted when a non-core node's current_hp reaches 0. BattleSystem listens
## and runs the forced-deallocation cascade (dealloc + wound + core HP loss).
signal skill_node_depleted(node: SkillNode)

## The same instant as [signal skill_node_depleted], but carrying the owner the
## node is about to lose. Both fire from `SkillNode.take_damage`; this one exists
## because `skill_node_depleted`'s own handler (BattleSystem's cascade) CLEARS
## `owned_by`, and connection order is tree order — so a second consumer that
## needs to know *whose* node died cannot safely read it off the node. Carry the
## fact on the signal instead of racing for it. (Same reasoning as the
## entity_dying / entity_died phase split, one scale down.)
##
## Fires for the destroyed node ONLY — never for the nodes the cascade islands
## off it. LootSystem pays per-node kill XP off this, and collateral islanding
## is not a kill.
signal skill_node_destroyed(node: SkillNode, defender: Entity)

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

## A defender's spike popped an incoming enemy blade vertex (#170) — the hostile
## vertex died on contact (and severed whatever it dragged off the handle). Fired
## from the live swing at the contact moment. [param defender] is the spiked node
## that popped it, [param attacker] whose blade it was, [param position] the
## contact point. VFX hooks listen to play the pop burst; a future spike-reload
## system (#189) can count charges off this without touching the detection.
signal blade_vertex_popped(defender: SkillNode, attacker: Entity, position: Vector2)

## Floating-tooltip signals for SpellPickerButton hover. [SpellTooltip]
## subscribes to both; the button emits on mouse_entered / mouse_exited.
## [param caster] is the player entity whose stats may modify spell values.
signal spell_hovered(spell: SpellDef, caster: Entity)
signal spell_unhovered

## Fired by GameRoot when the player entity dies — the HUD shows the game-over
## overlay. No payload; the single overlay is pre-composed and just toggles visible.
signal game_over
