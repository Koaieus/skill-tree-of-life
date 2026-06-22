@abstract
class_name EntityController
extends Node

## Drives an [Entity] through its turn. Subscribes to
## [signal TurnManager.turn_started] and dispatches to [method take_turn]
## when the wired entity is the active one.
##
## Player entities use [PlayerInputController] (a sibling system, event-driven
## off UI clicks) rather than an EntityController — humans don't need a
## decision-making hook, just an input adapter. EntityController is the
## self-driven path: AI today, scripted setpieces tomorrow.
##
## Auto-resolves [member entity] from its parent if left null, so attaching as
## a child of an Entity is enough wiring.

@export var entity: Entity = null

var _turn_manager: TurnManager


func _ready() -> void:
	if entity == null:
		entity = get_parent() as Entity
	if entity == null:
		push_warning("%s has no entity wired and no Entity parent; idle" % name)
		return
	_turn_manager = get_tree().get_first_node_in_group(TurnManager.GROUP) as TurnManager
	if _turn_manager == null:
		push_warning("%s found no TurnManager; idle" % name)
		return
	_turn_manager.turn_started.connect(_on_turn_started)


func _on_turn_started(active: Entity) -> void:
	if active != entity:
		return
	take_turn()


## Override. Decide and execute this entity's turn, then call
## [method TurnManager.end_turn]. May await — VFX, animations, etc.
@abstract func take_turn() -> void
