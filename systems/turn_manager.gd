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
	current_entity = entity
	turn_started.emit(entity)


## End the current turn.
## Deducts 100 initiative from the entity, then auto-ticks until the next
## entity is ready and starts their turn.
func end_turn() -> void:
	if current_entity == null:
		return
	var entity := current_entity
	current_entity = null
	turn_ended.emit(entity)
	entity.initiative_current -= 100.0
	_tick_until_ready(entity)


## Tick the initiative clock by one unit. Advances every entity in the
## "entities" group by their initiative_speed value.
func tick() -> void:
	ticked.emit()
	for node in get_tree().get_nodes_in_group("entities"):
		var e := node as Entity
		if e == null or e.stat_board == null or e.stat_board.initiative_speed == null:
			continue
		e.initiative_current += float(e.stat_board.initiative_speed.value)


## Serve the next ready entity, or tick until one becomes ready.
## Checks BEFORE ticking so entities that all reached 100 in the same cycle
## are each served before the clock advances again.
## `last` is the entity that just ended its turn — deprioritised on ties so
## it doesn't immediately win its own initiative tie.
func _tick_until_ready(last: Entity = null, max_ticks: int = 1000) -> void:
	for _i in max_ticks:
		var ready_entities: Array[Entity] = []
		for node in get_tree().get_nodes_in_group("entities"):
			var e := node as Entity
			if e != null and e.initiative_current >= 100.0:
				ready_entities.append(e)
		if not ready_entities.is_empty():
			ready_entities.sort_custom(func(a: Entity, b: Entity) -> bool:
				if a.initiative_current != b.initiative_current:
					return a.initiative_current > b.initiative_current
				return b == last  # tiebreak: just-acted entity goes last
			)
			start_turn(ready_entities[0])
			return
		tick()
	push_warning("TurnManager: no entity reached 100 initiative in %d ticks" % max_ticks)
