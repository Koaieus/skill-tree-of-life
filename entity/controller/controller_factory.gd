class_name ControllerFactory
extends Node
## The one place an [EntityController] is built and attached. Every entity
## the turn loop may hand a turn to carries exactly one controller child:
## [PlayerController] when [member Entity.is_human_controlled], an
## [AIController] otherwise. Composed under `Systems` in `game_root.tscn`; the
## three exports are what an [AIController] needs to submit and score, handed
## to each one it builds.
##
## An explicitly composed controller always wins: [method ensure_all] skips an
## entity that already has one.

@export var command_applier: CommandApplier
@export var battle_system: BattleSystem
@export var loot_system: LootSystem


## The entity's controller child, or null. First match in child order — which
## is why [method replace_with_ai] detaches the old one rather than only
## queueing it.
static func find(ent: Entity) -> EntityController:
	for child in ent.get_children():
		if child is EntityController:
			return child as EntityController
	return null


## A fresh, unattached controller for [param ent]: [PlayerController] if a
## human drives it, [method make_ai] otherwise.
func make_for(ent: Entity) -> EntityController:
	if ent.is_human_controlled:
		var pc := PlayerController.new()
		pc.name = "PlayerController"
		return pc
	return make_ai(ent)


## The one place an [AIController] is built. Its tier is the seat's
## [member Participant.ai_tier], looked up in [member GameSession.roster] by
## [member Entity.participant_id]; with no roster or no matching seat (a
## hand-authored sandbox) the controller keeps [constant AIController.DEFAULT_TIER].
## Nothing else in production writes [member AIController.ai_tier].
func make_ai(ent: Entity) -> AIController:
	var ai := AIController.new()
	ai.name = "AIController"
	ai.command_applier = command_applier
	ai.battle_system = battle_system
	ai.loot_system = loot_system
	if GameSession.roster != null and ent.participant_id != 0:
		# Untyped on purpose: `Participant` is `session/`, above this module —
		# naming it here would grow an upward dependency edge.
		var seat = GameSession.roster.by_id(ent.participant_id)
		if seat != null:
			ai.ai_tier = seat.ai_tier as AIController.Tier
	return ai


## Attach a controller to every [constant Entity.GROUP] member that has none.
## Idempotent — the level runs it after `_setup_level` and again whenever an
## arriving world brings entities with it.
##
## Reads [member Entity.is_human_controlled] rather than comparing identity
## against a "player" — that authored-per-entity flag is what
## [method GameRoot.apply_roster] sets from a [Participant]'s kind, and what a
## hand-authored scene sets directly on its node (#475).
func ensure_all() -> void:
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
		var ent := node as Entity
		if ent == null or find(ent) != null:
			continue
		ent.add_child(make_for(ent))


## Swap [param ent]'s controller for an [AIController] and return it. The old
## one is detached NOW, not only queued: [method find] walks children in order
## and a still-parented [PlayerController] would keep winning until the frame's
## free flush. An entity already AI-driven keeps its controller. [param ai],
## when given, is attached instead of a [method make_ai] one (a bench's probe).
func replace_with_ai(ent: Entity, ai: AIController = null) -> AIController:
	var old := find(ent)
	if ai == null:
		if old is AIController:
			return old as AIController
		ai = make_ai(ent)
	if old != null:
		ent.remove_child(old)
		old.queue_free()
	ent.add_child(ai)
	return ai
