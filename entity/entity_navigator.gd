@tool
class_name EntityNavigator
extends GraphMirror

## Per-entity owned-subgraph mirror. Only nodes where `owned_by == entity`
## enter the mirror — i.e. the entity's induced subgraph.
##
## Drives connectivity questions like "would deallocating this node island
## any of my other owned nodes from my core?"
## ([code]would_disconnect_from(node, core_location)[/code]). Combat code
## reads the inherited `astar` directly for path / reach queries on the
## owned territory.
##
## Mutation contract: ownership writes happen through [AllocationSystem],
## which calls [method GraphMirror.mirror_add] / [method GraphMirror.mirror_remove]
## on us. We don't subscribe to per-node `owner_changed` — programmatic
## `node.owned_by = X` outside the system would drift the mirror. Structural
## edge changes still come via graph signals so procgen / runtime topology
## edits stay in sync.

@export var entity: Entity


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if entity == null:
		push_warning("EntityNavigator has no Entity reference")
		return
	if graph == null:
		push_warning("EntityNavigator has no Graph reference")
		return
	wire_to(graph)


func _should_mirror(node: SkillNode) -> bool:
	return node.owned_by == entity
