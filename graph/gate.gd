@tool
class_name Gate
extends Node2D

## A togglable connection between two [SkillNode]s, owned by the [Graph] under
## its `gates_container`. Same authoring shape as [Edge] (`from` / `to`).
##
## [b]State is never stored.[/b] Open means a real [Edge] exists between the
## endpoints, closed means none does; [method Graph.flip_gates] removes or adds
## that edge, so every mirror follows through the ordinary edge signals.
## See `docs/design/skill_node_addons.md` § Gate.

@export var from: SkillNode
@export var to: SkillNode


## The Graph this gate belongs to — the nearest [Graph] ancestor, or null.
func get_graph() -> Graph:
	var p := get_parent()
	while p != null and not (p is Graph):
		p = p.get_parent()
	return p as Graph


## Is there a real edge between the endpoints right now?
func is_open() -> bool:
	return false


## May [param entity] flip this gate? Iff it owns at least one endpoint and the
## other is neutral or its own. An identity question, not an `ownership_bit`
## relation: an ally owning the far end is another entity, so it freezes the
## gate too — flipping may neither cut someone else's edge nor bridge onto an
## occupied node.
func can_toggle(_entity: Entity) -> bool:
	return false
