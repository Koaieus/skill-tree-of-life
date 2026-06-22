class_name AIController
extends EntityController

## Skip-turn AI. Waits a beat (so the player can register whose turn it was)
## and immediately ends the turn. Placeholder for a real policy: future
## subclasses or strategy resources will pick allocations, attacks, etc.,
## before calling end_turn.

## Seconds to pause before ending the turn. Cosmetic — gives the human a
## visual cue that an NPC just acted.
@export var turn_delay: float = 0.2


func take_turn() -> void:
	if turn_delay > 0.0:
		await get_tree().create_timer(turn_delay).timeout
	if _turn_manager != null:
		_turn_manager.end_turn()
