class_name NodeStatus
extends RefCounted

## One status currently on a node — the per-node RUNTIME half of a
## [StatusDef] (#872), held in [NodeCombat]'s status slice. A UI reads it as
## one row: `(def.display_name, def.tint, def.icon, power / def.power_max)`.

var def: StatusDef
var power: float = 0.0


func _init(p_def: StatusDef = null, p_power: float = 0.0) -> void:
	def = p_def
	power = p_power


## `power / def.power_max` in 0..1 — the fill of a status bar.
func normalised() -> float:
	if def == null or def.power_max <= 0.0:
		return 0.0
	return clampf(power / def.power_max, 0.0, 1.0)


## A detached copy for a shadow — same shared def, own power.
func clone() -> NodeStatus:
	return NodeStatus.new(def, power)
