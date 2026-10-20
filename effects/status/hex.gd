@tool
class_name HexStatus
extends StatusDef

## Hex: every stack plants a node-local ADD_BONUS on `status_resistance` of
## `-resist_per_stack × stacks`. `status_resistance` is the family parent of
## every `<aspect>_resistance` (ADR 0029), so the one modifier shreds them
## all, after any INCREASE or MULTIPLY on the resistance. Uncapped: past the
## node's own resistance the read goes negative, and [method
## StatusHost.effective_power] lands MORE stacks than were sent
## (vulnerability). The def owns none of that arithmetic. Hex has no
## resistance of its own, so it cannot shred or resist itself.
##
## Same shared-stateless shape as [WitherStatus]: the per-node handle is
## FOUND, and every write REPLACES the found modifier — a static modifier is
## SHARED between a live board and its shadow clone, so mutating `value` from
## a shadow resolve would write the live world before any [AttackRecord]
## replays (`.claude/rules/attack-timeline.md`).

## Resistance lost per stack — `0.1` means 10 stacks strip 100% (an immune
## node opens) and 20 on a bare node read −100% (twice the stacks land).
## A tuning knob on the def, never a constant in a formula.
@export_range(0.0, 1.0, 0.01, "or_greater") var resist_per_stack: float = 0.1


## The authored modifier, duplicated per application. A script-class
## [code]is[/code] check tells a found modifier apart from any other
## ADD_BONUS on `status_resistance`.
const HexModifier := preload("res://effects/status/modifiers/hex_modifier.gd")
const _MODIFIER_TEMPLATE := preload("res://effects/status/modifiers/hex_modifier.tres")


func _on_applied(host, power: float) -> void:
	_set_hex(host, power)


## Fires BEFORE decay lands; [param after] is the power the node is about to
## hold. At `after == 0` the slice removes the status right after this, and
## [method _on_removed] strips the modifier.
func _on_tick(host, _before: float, after: float) -> void:
	_set_hex(host, after)


func _on_removed(host) -> void:
	var m := _find(host)
	if m != null:
		host.remove_local_modifier(m)


func _set_hex(host, power: float) -> void:
	var old := _find(host)
	if old != null:
		host.remove_local_modifier(old)
	if power <= 0.0:
		return
	var m: StatModifier = _MODIFIER_TEMPLATE.duplicate()
	m.value = -resist_per_stack * power
	host.add_local_modifier(m)


## The [HexModifier] on [param host]'s local `status_resistance`, or null.
## ADD_BONUS folds into a scalar bin, so this walks the stat's applied list
## (the same walk [CurseStatus] does).
func _find(host) -> StatModifier:
	var b: StatBoard = host.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(&"status_resistance")
	if s == null:
		return null
	for m in s._modifiers:
		if m is HexModifier:
			return m
	return null
