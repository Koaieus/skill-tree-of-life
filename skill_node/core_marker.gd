@tool
extends Node2D

## Star-only marker for the owning entity's core node. The bright inner disk
## that used to live here moved to BaseCircle so every allocated node renders
## it; CoreMarker is now purely the "this is the core" stamp via its Label
## child. `configure` stays a no-op-on-color (the star is hard-coded) so
## SkillNode's existing call site doesn't have to branch.

var _radius: float = 32.0


func configure(r: float, _color: Color) -> void:
	_radius = r
	queue_redraw()
