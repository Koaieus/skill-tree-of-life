@tool
class_name PhaseBodyBase
extends VBoxContainer

## Base for the swappable bodies of [PhaseContextPanel]. Each body knows
## about one phase, builds its own widgets, and self-subscribes to the stats
## / systems it needs. [PhaseContextPanel] just instantiates the right body
## scene per [TurnManager.Phase] and hands it the live entity + systems.
##
## Bodies are [code]@tool[/code] so designers can open their .tscn and tune
## styling against placeholder content (each subclass renders a sensible
## editor preview when [code]entity == null[/code]).

var entity: Entity = null
var battle_system: BattleSystem = null


func bind(p_entity: Entity, p_battle_system: BattleSystem) -> void:
	entity = p_entity
	battle_system = p_battle_system
	if is_node_ready():
		rebuild()


func _ready() -> void:
	rebuild()


## Subclasses override. Always called once after _ready and once per
## bind() — keep it idempotent and feel free to wipe + re-emit children.
func rebuild() -> void:
	pass
