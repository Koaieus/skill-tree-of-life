class_name TurnManager
extends Node

## Turn-by-turn coordination. Owns:
##   - who currently has the turn (`current_entity`)
##   - which of the three phases that entity is in (`current_phase`)
##   - initiative bookkeeping (when Stat exists)
##
## Per the GDD: initiative ticks until 100 → entity acts → three phases
## of one turn → end_turn deducts 100 initiative and the cycle resumes.
## A single SP pool spans all three phases (no temp/permanent split —
## the phase IS that flag).

enum Phase {
	DEPLOYMENT,    # Allocate / deallocate, reposition the constellation
	BATTLE,        # Attack & defend; action_points consumed here
	CONSOLIDATION, # Cleanup, promotions, lock-ins, end-of-turn ticks
}

signal ticked
signal turn_started(entity: Entity)
signal phase_changed(entity: Entity, phase: Phase)
signal turn_ended(entity: Entity)

## The entity currently taking its turn; null between turns.
var current_entity: Entity = null
## The phase that `current_entity` is currently in. Meaningless if
## `current_entity == null`.
var current_phase: Phase = Phase.DEPLOYMENT


## Hand the turn to `entity`. Phase resets to DEPLOYMENT.
func start_turn(entity: Entity) -> void:
	assert(entity != null, "TurnManager.start_turn(null)")
	assert(current_entity == null, "Already in a turn: %s" % current_entity)
	current_entity = entity
	current_phase = Phase.DEPLOYMENT
	turn_started.emit(entity)
	phase_changed.emit(entity, current_phase)


## Advance to the next phase. Returns true on a real transition, false
## if already at CONSOLIDATION (caller should then `end_turn()`).
func advance_phase() -> bool:
	if current_entity == null:
		return false
	match current_phase:
		Phase.DEPLOYMENT:
			current_phase = Phase.BATTLE
		Phase.BATTLE:
			current_phase = Phase.CONSOLIDATION
		Phase.CONSOLIDATION:
			return false
	phase_changed.emit(current_entity, current_phase)
	return true


## End the current turn. Caller is responsible for having reached
## CONSOLIDATION (or for explicitly bailing early).
## Deducts 100 initiative from the entity, then auto-ticks until the next
## entity is ready and starts their turn.
func end_turn() -> void:
	if current_entity == null:
		return
	var entity := current_entity
	current_entity = null
	turn_ended.emit(entity)
	entity.initiative_current -= 100.0
	_tick_until_ready()


## Tick the initiative clock by one unit. Advances every entity in the
## "entities" group by their initiative_speed value.
func tick() -> void:
	ticked.emit()
	for node in get_tree().get_nodes_in_group("entities"):
		var e := node as Entity
		if e == null or e.stat_board == null or e.stat_board.initiative_speed == null:
			continue
		e.initiative_current += float(e.stat_board.initiative_speed.value)


## Tick until at least one entity has initiative >= 100, then start the turn
## for the highest-initiative entity among the ready set.
## Guards against all-zero-speed edge cases with a tick cap.
func _tick_until_ready(max_ticks: int = 1000) -> void:
	for _i in max_ticks:
		tick()
		var ready_entities: Array[Entity] = []
		for node in get_tree().get_nodes_in_group("entities"):
			var e := node as Entity
			if e != null and e.initiative_current >= 100.0:
				ready_entities.append(e)
		if not ready_entities.is_empty():
			ready_entities.sort_custom(func(a: Entity, b: Entity) -> bool:
				return a.initiative_current > b.initiative_current)
			start_turn(ready_entities[0])
			return
	push_warning("TurnManager: no entity reached 100 initiative in %d ticks" % max_ticks)


## Returns true if an allocation/deallocation is currently permitted.
func can_allocate() -> bool:
	return current_entity != null and current_phase == Phase.DEPLOYMENT


## Returns true if a combat action is currently permitted.
func can_act() -> bool:
	return current_entity != null and current_phase == Phase.BATTLE
