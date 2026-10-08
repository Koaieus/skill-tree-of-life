class_name WeaknessStatus
extends StatusDef

## Weakness (`weakened`): a weakening hex that cuts the damage DEALT by attacks
## originating from the host — one `MULTIPLY` on each of the local
## `ranged_damage`, `blade_damage` and `spell_damage`, at [method factor_for]
## of the TOTAL power, Blindness's saturating curve. The three attack modes
## already read the origin's local value (the firing slice, the blade node,
## the spell source), so nothing downstream changes. Raw damage only.
##
## Host: a node cuts that node alone; an entity (a core's status, read
## entity-wide) plants on the entity board, which folds under every owned
## node's local read — so a node's N and its owner's M multiply with no extra
## code. Find-and-replace, never edit in place: see [BlindnessStatus] for why
## (a static modifier is shared between a live board and its shadow clone).

const STAT_IDS: Array[StringName] = [&"ranged_damage", &"blade_damage", &"spell_damage"]

## The power at which damage is halved — the curve's half-depth. The owner's
## knob (`weakened.tres`); no test pins the authored value.
@export var half_depth: float = 5.0
## The multiplier the curve saturates to — a weakened host always keeps this.
@export var floor_factor: float = 0.1


## The local multiplier Weakness plants — its own type so a stateless def can
## find it again, and UNSCALED so the cut does not ladder with allocation level.
const WeaknessModifier := preload("res://effects/status/modifiers/weakness_modifier.gd")
const _MODIFIER_TEMPLATE := preload("res://effects/status/modifiers/weakness_modifier.tres")


func _on_applied(host, power: float) -> void:
	_set_factor(host, power)


## Fires BEFORE decay lands; [param after] is the power about to be held. At
## `after == 0` the status is removed right after and [method _on_removed]
## strips the modifiers.
func _on_tick(host, _before: float, after: float) -> void:
	_set_factor(host, after)


func _on_removed(host) -> void:
	for stat_id in STAT_IDS:
		var m := _find(host, stat_id)
		if m != null:
			host.remove_local_modifier(m)


## The multiplier for [param power] — the curve's only home:
## `max(floor, k / (power + k))`, `1.0` at zero, `½` at [member half_depth],
## strictly decreasing until it meets [member floor_factor].
func factor_for(power: float) -> float:
	if power <= 0.0 or half_depth <= 0.0:
		return 1.0
	return maxf(floor_factor, half_depth / (power + half_depth))


func _set_factor(host, power: float) -> void:
	var f := factor_for(power)
	for stat_id in STAT_IDS:
		var old := _find(host, stat_id)
		if old != null:
			host.remove_local_modifier(old)
		var m: StatModifier = _MODIFIER_TEMPLATE.duplicate()
		m.stat_id = stat_id
		m.value = f
		host.add_local_modifier(m)


## The [WeaknessModifier] on [param host]'s local [param stat_id], or null.
func _find(host, stat_id: StringName) -> StatModifier:
	var b: StatBoard = host.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(stat_id)
	if s == null:
		return null
	for m in s.bins.multipliers:
		if m is WeaknessModifier:
			return m
	return null
