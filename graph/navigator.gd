@tool
class_name Navigator
extends GraphMirror

## Full-graph mirror. Reflects every SkillNode and Edge in the [Graph], so
## path queries and structural questions can run against the live world
## without walking the scene tree.
##
## Inherits all queries from [GraphMirror]; this subclass only wires the
## auto-sync. `_should_mirror` falls through to the base default (true).


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if graph == null:
		push_warning("Navigator has no Graph reference")
		return
	wire_to(graph)
