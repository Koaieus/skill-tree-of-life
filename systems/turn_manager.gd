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
func end_turn() -> void:
	if current_entity == null:
		return
	var entity := current_entity
	current_entity = null
	turn_ended.emit(entity)
	# TODO: deduct 100 from entity's initiative; pick the next ready
	# entity. Both wait on the v2 Stat to land.


## Tick the clock by one unit. Stub: just emits so listeners can
## already hook in. Initiative progression + ready-queue cycle land
## once entities carry an initiative Stat.
func tick() -> void:
	ticked.emit()
	# TODO: for each entity in `entities` group, progress initiative;
	# if any crosses 100, start its turn (or queue it).
