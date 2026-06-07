@tool
class_name Entity
extends Node

## An entity that lives on the skill tree. Owns a connected induced
## subgraph of SkillNodes. Identity + colour + an optional stat board, plus
## a child `EntityNavigator` that mirrors the owned-subgraph for connectivity
## queries (islanding checks now; combat path/reach queries later).

signal core_location_changed

@export var display_name: String = "Entity"
@export var color: Color = Color.WHITE
@export var stat_board: StatBoard = null
@export var core_location: SkillNode:
	set(value):
		if core_location == value:
			return
		core_location = value
		core_location_changed.emit()

## Auto-created on _ready when the entity has a Graph ancestor. Stays null
## in editor (`@tool` short-circuit) and in stand-alone tests with no graph.
var navigator: EntityNavigator


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var g := _find_graph()
	if g == null:
		push_warning("Entity '%s' has no Graph ancestor; navigator disabled" % display_name)
		return
	navigator = EntityNavigator.new()
	navigator.name = "EntityNavigator"
	navigator.entity = self
	navigator.graph = g
	add_child(navigator)


func _find_graph() -> Graph:
	var n: Node = get_parent()
	while n != null:
		if n is Graph:
			return n as Graph
		n = n.get_parent()
	return null


func _to_string() -> String:
	return "Entity<%s--%s>" % [display_name, core_location as Variant if core_location else 'N/A']
