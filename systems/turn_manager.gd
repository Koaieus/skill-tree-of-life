extends Node
class_name TurnManager

# Signals
signal ticked
signal turn_started(entity: TreeEntity)
signal turn_ended
signal deadlock_detected

# === Settings ===
@export_range(5, 1000, 1, "suffix:turns") var max_cycles_without_turn: int = 100
@export var auto_reset_deadlock_counter: bool = false

# === State ===
var entity_at_turn: TreeEntity = null
var _cycle_count_without_turn: int = 0
var _is_processing_turn_cycle: bool = false

# === Public API ===
func request_turn_cycle() -> void:
	if _is_processing_turn_cycle:
		return  # avoid duplicate calls

	_is_processing_turn_cycle = true
	await _run_turn_cycle()
	_is_processing_turn_cycle = false

# === Internal ===
func _get_ready_entities() -> Array[TreeEntity]:
	var ready: Array[TreeEntity] = []
	for entity: TreeEntity in _get_all_active_entities():
		if entity.stats.initiative.progress >= 100:
			ready.append(entity)
	return ready

func _get_all_active_entities() -> Array[TreeEntity]:
	var result: Array[TreeEntity] = []
	for entity: TreeEntity in get_tree().get_nodes_in_group("initiative-ready"):
		if entity.can_take_turn():
			result.append(entity)
	return result

func _reset_deadlock_counter() -> void:
	_cycle_count_without_turn = 0

func _run_turn_cycle() -> void:
	var ready_entities: Array[TreeEntity] = _get_ready_entities()

	# Outer loop — tick clock while no entities ready
	while ready_entities.is_empty():
		emit_signal("ticked")
		_cycle_count_without_turn += 1

		if _cycle_count_without_turn >= max_cycles_without_turn:
			emit_signal("deadlock_detected")
			if auto_reset_deadlock_counter:
				_reset_deadlock_counter()
			return

		await get_tree().process_frame  # let visuals update
		ready_entities = _get_ready_entities()

	# Found ready entities — reset deadlock counter
	_reset_deadlock_counter()

	# Inner loop — process ready entities
	while not ready_entities.is_empty():
		entity_at_turn = ready_entities[0]
		emit_signal("turn_started", entity_at_turn)

		# Wait for this entity to end its turn
		await self.turn_ended
		print('[TURN: ENDED for %s]' % entity_at_turn)

		# Deduct initiative progress
		entity_at_turn.stats.initiative.progress -= 100

		ready_entities = _get_ready_entities()


func _on_deadlock_detected() -> void:
	assert(false, 'Deadlock detected')

func _on_turn_ended() -> void:
	request_turn_cycle.call_deferred()
