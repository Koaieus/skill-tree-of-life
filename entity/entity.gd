@tool
class_name Entity
extends Node

## An entity that lives on the skill tree. Owns a connected induced
## subgraph of SkillNodes. For now: just identity + colour + an optional
## stat board. Behaviour (allocation, turns, combat) layers on later.

@export var display_name: String = "Entity"
@export var color: Color = Color.WHITE
@export var stat_board: StatBoard = null


func _to_string() -> String:
	return "Entity<%s>" % display_name
