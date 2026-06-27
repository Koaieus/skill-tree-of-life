@tool
class_name IdleBody
extends ContextBodyBase

## Default context body: a short hint, no data dump (the left StatsPanel already
## shows the player's pools). Shown when nothing else claims the panel.

@onready var _hint: Label = $Hint


func rebuild() -> void:
	if not is_node_ready():
		return
	_hint.text = "Right-click a node to inspect it. Click your core to move it; pick a mode below to attack."
