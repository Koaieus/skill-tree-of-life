class_name TurnManager
extends Node

## Turn-by-turn coordination. Owns:
##   - who currently has the turn (`current_entity`)
##   - initiative bookkeeping
##
## Per the GDD: initiative ticks until 100 → entity acts → end_turn deducts
## 100 initiative and the cycle resumes. A single implicit phase per turn:
## all per-turn budgets (AP / DP / SP / XP / mana / wound-heal / node-refill)
## replenish at `turn_started` and the entity spends them in any order until
## End Turn. Intent (allocate vs deallocate vs attack vs cast vs move-core) is
## disambiguated by INPUT CHANNEL, not by phase — see PlayerInputController.

signal ticked
signal turn_started(entity: Entity)
signal turn_ended(entity: Entity)

## The entity currently taking its turn; null between turns.
var current_entity: Entity = null

## Turns served since the level started — every [method start_turn], across all
## entities, not rounds. [RunOutcome.turn_count] reports it (#460).
var turns_taken: int = 0


## Group used by Entity to discover the level's TurnManager without coupling
## to scene-tree depth. Single instance per level.
const GROUP := &"turn_manager"


func _enter_tree() -> void:
	add_to_group(GROUP)


## Hand the turn to `entity`. Turn-start upkeep (budget replenish) runs in
## Entity._on_turn_started, subscribed to `turn_started`.
func start_turn(entity: Entity) -> void:
	assert(entity != null, "TurnManager.start_turn(null)")
	assert(current_entity == null, "Already in a turn: %s" % current_entity)
	# Consume readiness: the entity must climb to its cap again for the next turn.
	entity.remove_from_group(Entity.READY_GROUP)
	current_entity = entity
	turns_taken += 1
	turn_started.emit(entity)


## End the current turn, then auto-tick until the next entity is ready and
## starts their turn. The acting entity's initiative was already deducted at
## fill time (CyclicPoolStatDef carries the overshoot forward), so there is no
## deduction here.
func end_turn() -> void:
	if current_entity == null:
		return
	var entity := current_entity
	current_entity = null
	turn_ended.emit(entity)
	_tick_until_ready(entity)


## Tick the initiative clock by one unit. Replenishes every entity's `initiative`
## pool by its initiative_speed; a pool that crosses its cap fires `replenished`,
## which the entity handles by joining Entity.READY_GROUP (and the cyclic def
## carries the overshoot into the next cycle).
func tick() -> void:
	ticked.emit()
	for node in get_tree().get_nodes_in_group(Entity.GROUP):
		var e := node as Entity
		if e == null or e.stat_board == null:
			continue
		if e.stat_board.initiative == null or e.stat_board.initiative_speed == null:
			continue
		e.stat_board.initiative.replenish(float(e.stat_board.initiative_speed.value))


## Serve the next ready entity, or tick until one becomes ready.
## Checks BEFORE ticking so entities that crossed the cap in the same cycle are
## each served before the clock advances again. Ready entities are those in
## Entity.READY_GROUP; ties break by carried initiative (more overshoot first),
## then `last` (the just-acted entity) is deprioritised so it can't immediately
## win its own tie.
func _tick_until_ready(last: Entity = null, max_ticks: int = 1000) -> void:
	for _i in max_ticks:
		var ready_entities: Array[Entity] = []
		for node in get_tree().get_nodes_in_group(Entity.READY_GROUP):
			var e := node as Entity
			if e != null:
				ready_entities.append(e)
		if not ready_entities.is_empty():
			ready_entities.sort_custom(func(a: Entity, b: Entity) -> bool:
				var ai := a.stat_board.initiative.current if a.stat_board != null and a.stat_board.initiative != null else 0.0
				var bi := b.stat_board.initiative.current if b.stat_board != null and b.stat_board.initiative != null else 0.0
				if ai != bi:
					return ai > bi
				return b == last  # tiebreak: just-acted entity goes last
			)
			start_turn(ready_entities[0])
			return
		tick()
	push_warning("TurnManager: no entity reached its initiative cap in %d ticks" % max_ticks)
