class_name NodeStatus
extends RefCounted

## One status row on a host — the per-host RUNTIME half of a [StatusDef]
## (#872), held in a [StatusHost] slice under `(def.id, key)` (#1343). A UI
## reads it as one row: `(def.display_name, def.tint, def.icon, normalised())`,
## its count gated by [method StatusDef.count_visible].

var def: StatusDef
## The stack count — always whole (ADR 0032). A fraction is rounded where it
## is minted (the fold, a decay, a spill), never here.
var power: int = 0
## The row's grouping key ([method StatusDef.group_key]): `true` for a shared
## row; otherwise a bool, int or StringName — never an Object.
var key: Variant = true
## The LATEST applier's camp ([member Faction.id], `&""` none) and
## [member Entity.entity_id] (`0` none) — [member StatusDef.visible_if] reads them.
var camp_id: StringName = &""
var applier_id: int = 0
## Rest ticks since the row last decayed from a fresh start — read by a
## ramping [StatusDecay] ([RampDecay]). [method StatusHost.tick_statuses]
## advances it after each decay; an exertion resets it to `0`.
var decay_step: int = 0


func _init(p_def: StatusDef = null, p_power: int = 0, p_key: Variant = true) -> void:
	def = p_def
	power = p_power
	key = p_key


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


## A detached copy for a shadow — same shared def, own power, same key and applier.
func clone() -> NodeStatus:
	var c := NodeStatus.new(def, power, key)
	c.camp_id = camp_id
	c.applier_id = applier_id
	c.decay_step = decay_step
	return c
