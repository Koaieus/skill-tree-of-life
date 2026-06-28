extends GameRoot

## Hand-authored sandbox. Inherits GameRoot defaults — the `%Player` node
## baked into dev_sandbox.tscn is picked up by GameRoot._setup_level.

func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	$UI.visible = true
	
