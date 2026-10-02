class_name NodeStatus
extends RefCounted

## One status currently on a node — the per-node RUNTIME half of a
## [StatusDef] (#872), held in [NodeCombat]'s status slice. A UI reads it as
## one row: `(def.display_name, def.tint, def.icon, normalised())`.

var def: StatusDef
## The stack count — always whole (ADR 0032). A fraction is rounded where it
## is minted (the fold, a decay, a spill), never here.
var power: int = 0


func _init(p_def: StatusDef = null, p_power: int = 0) -> void:
	def = p_def
	power = p_power


## `power / anchor` in 0..1 — the fill of a status bar and the node tint's
## strength. The anchor is [member StatusDef.display_max] when authored, else
## [member StatusDef.power_max] (#962: an uncapped def needs the former).
func normalised() -> float:
	if def == null:
		return 0.0
	var anchor := def.display_max if def.display_max > 0.0 else def.power_max
	if anchor <= 0.0:
		return 0.0
	return clampf(power / anchor, 0.0, 1.0)


## A detached copy for a shadow — same shared def, own power.
func clone() -> NodeStatus:
	return NodeStatus.new(def, power)
