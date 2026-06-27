@tool
class_name ContextBodyBase
extends VBoxContainer

## Base for the swappable bodies of [ContextPanel]. Each body owns one context
## (active attack plan, core-move targeting, a pinned node, idle), builds its own
## widgets, and self-subscribes to whatever systems it needs. [ContextPanel] just
## instantiates the right body scene per resolved context and hands it the live
## entity + systems + the relevant node.
##
## Bodies are [code]@tool[/code] so designers can open their .tscn and tune
## styling against placeholder content (each subclass renders a sensible editor
## preview when its inputs are null). This inherited-scene split is the whole
## point: pre-author bespoke stylings per context cheaply.

var entity: Entity = null
var battle_system: BattleSystem = null
var input_ctl: PlayerInputController = null
## The node this context centres on (pinned node, core slot), or null.
var context_node: SkillNode = null


func bind(p_entity: Entity, p_battle_system: BattleSystem,
		p_input_ctl: PlayerInputController, p_node: SkillNode = null) -> void:
	entity = p_entity
	battle_system = p_battle_system
	input_ctl = p_input_ctl
	context_node = p_node
	if is_node_ready():
		rebuild()


func _ready() -> void:
	rebuild()


## Subclasses override. Called once after _ready and once per bind() — keep it
## idempotent and feel free to wipe + re-emit children.
func rebuild() -> void:
	pass
