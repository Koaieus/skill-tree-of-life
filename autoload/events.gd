@tool
extends Node

signal skill_node_hovered(node: SkillNode)
signal skill_node_unhovered

## Re-emitted by SkillNode.take_damage so UI (floating damage numbers, screen
## shake, etc.) can subscribe once globally instead of binding to every node.
signal skill_node_damaged(node: SkillNode, amount: float, source: Variant)

## Emitted when a non-core node's current_hp reaches 0. BattleSystem listens
## and runs the forced-deallocation cascade (dealloc + wound + core HP loss).
signal skill_node_depleted(node: SkillNode)

## Re-emission of [signal SkillPointStat.wounds_applied] / [signal SkillPointStat.wounds_healed]
## keyed by the owning entity. Entity itself does the re-emit so the global
## bus carries the entity reference (a stat doesn't know its owner). UI floater
## layers subscribe here instead of binding to every entity's SP stat.
signal entity_wounded(entity: Entity, amount: int)
signal entity_healed(entity: Entity, amount: int)
## Emitted once when an entity's core health hits 0 (see Entity.die). Systems
## react off the bus: LootSystem grants the killer XP + drops SkillDust loot
## (runs FIRST — needs the corpse's nodes still owned), AllocationSystem strips
## its owned nodes, GameRoot handles the player-vs-NPC consequence. Killer
## attribution is NOT carried here — LootSystem resolves it from its injected
## TurnManager (current_entity at the synchronous death), keeping Entity dumb.
signal entity_died(entity: Entity)

## Emitted when a spell's [IncidentReducer] resolves to null at a node
## (overlap-cancel, even-cancel, custom-cancel) — the spell visibly fizzles
## there. VFX hooks listen to pop a dissipate effect; battle log can record.
## Also lives on [member AttackOutcome.cancellations] as a list for replay.
signal spell_incident_cancelled(cancellation: SpellCancellation)
