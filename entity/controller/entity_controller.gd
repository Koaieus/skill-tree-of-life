@abstract
class_name EntityController
extends Node

## Drives an [Entity] through its turn. Listens to its own entity's
## [signal Entity.turn_began] — emitted by [method Entity.begin_turn] after the
## turn's upkeep — and never to a TurnManager, so attach order is irrelevant.
##
## Player entities use [PlayerInputController] (a sibling system, event-driven
## off UI clicks) rather than an EntityController — humans don't need a
## decision-making hook, just an input adapter. EntityController is the
## self-driven path: AI today, scripted setpieces tomorrow.
##
## Auto-resolves [member entity] from its parent if left null, so attaching as
## a child of an Entity is enough wiring.

@export var entity: Entity = null


func _ready() -> void:
	if entity == null:
		entity = get_parent() as Entity
	if entity == null:
		push_warning("%s has no entity wired and no Entity parent; idle" % name)
		return
	entity.turn_began.connect(take_turn)


## Override. Decide and execute this entity's turn, then call
## [method TurnManager.end_turn]. May await — VFX, animations, etc.
@abstract func take_turn() -> void
