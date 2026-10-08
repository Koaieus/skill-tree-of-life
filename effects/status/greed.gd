class_name GreedStatus
extends StatusDef

## Greed: the defender-side landing term lives in [StatusHost] (a debuff hit
## lands doubled and spends one stack); this def adds Avarice — every stack
## still held plants [member avarice_increase_per_stack] percent of `INCREASE`
## on the host's `bounty`, the stat [LootSystem] scales a removed node's kill
## XP by. A node host raises that node's payout; an entity host (a core's
## status, read entity-wide) plants on the entity board, which folds under
## every owned node's local read — so it scales the whole kill.
##
## Find-and-replace, never edit in place (see [BlindnessStatus] for why), and
## spends follow for free: a spend settles through `_on_applied` at the new
## count, and the last one through [method _on_removed].

const STAT_ID := &"bounty"

## The `INCREASE` (%) one Greed stack plants on `bounty`. Tentative owner knob.
@export var avarice_increase_per_stack: float = 10.0


## The bounty raise Greed plants — its own type so a stateless def can find it
## again, and UNSCALED so the Avarice does not ladder with allocation level.
const AvariceModifier := preload("res://effects/status/modifiers/avarice_modifier.gd")
const _MODIFIER_TEMPLATE := preload("res://effects/status/modifiers/avarice_modifier.tres")


func _on_applied(host, power: float) -> void:
	_set_avarice(host, power)


func _on_tick(host, _before: float, after: float) -> void:
	_set_avarice(host, after)


func _on_removed(host) -> void:
	var m := _find(host)
	if m != null:
		host.remove_local_modifier(m)


func _set_avarice(host, power: float) -> void:
	var old := _find(host)
	if old != null:
		host.remove_local_modifier(old)
	if power <= 0.0 or avarice_increase_per_stack == 0.0:
		return
	var m: StatModifier = _MODIFIER_TEMPLATE.duplicate()
	m.value = avarice_increase_per_stack * power
	host.add_local_modifier(m)


## The [AvariceModifier] on [param host]'s `bounty`, or null. INCREASE folds into
## a sum, so the handle is found in the stat's modifier list, not its bins.
func _find(host) -> StatModifier:
	var b: StatBoard = host.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(STAT_ID)
	if s == null:
		return null
	for m in s._modifiers:
		if m is AvariceModifier:
			return m
	return null
