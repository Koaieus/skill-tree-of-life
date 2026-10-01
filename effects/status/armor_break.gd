class_name ArmorBreakStatus
extends StatusDef

## Armor Break (#877, flat since #1308): `power` is a STACK COUNT and one stack
## is -1 node-local `armor`, uncapped — armor may go below zero, which
## [Mitigation] turns into extra damage before the `min_damage_taken` floor.
## `reapply = ACCUMULATE` in the authored def makes repeated hits add stacks.
## Recovery is its flat [member StatusDef.decay] per turn, same shape as everything else here.
##
## The def is shared and stateless (same rationale as [BlindnessStatus]): the
## per-node handle is FOUND rather than stored, and every write REPLACES the
## found modifier rather than editing it in place — a static modifier is
## SHARED between a live board and its shadow clone (`StatBoard._localize`
## copies only formula-bearing ones), so mutating a found modifier's `value`
## from a shadow resolve would write the live world before any [AttackRecord]
## replays (`.claude/rules/attack-timeline.md`). Remove + add lands on
## whichever board the [NodeCombat] owns and leaves the other alone.
##
## Like [CurseStatus], an additive handle has no public bin to walk, so
## [method _find] reads the stat's applied list directly.

## Own type so a found modifier can be told apart from any other ADD_BASE on
## `armor`, and UNSCALED so a broken node's armor loss is not laddered by
## allocation depth (#376 — same rationale as Blindness's BlindModifier).
class ArmorBreakModifier:
	extends StatModifier

	func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
		return StatModifier.UNSCALED


func _on_applied(host, power: float) -> void:
	_set_break(host, power)


## Fires BEFORE decay lands; [param after] is the power the node is about to
## hold. At `after == 0` the slice removes the status right after this, and
## [method _on_removed] strips the modifier.
func _on_tick(host, _before: float, after: float) -> void:
	_set_break(host, after)


func _on_removed(host) -> void:
	var m := _find(host)
	if m != null:
		host.remove_local_modifier(m)


func _set_break(host, power: float) -> void:
	var old := _find(host)
	if old != null:
		host.remove_local_modifier(old)
	if power <= 0.0:
		return
	var m := ArmorBreakModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = -power
	host.add_local_modifier(m)


## The [ArmorBreakModifier] on [param node]'s local `armor`, or null.
func _find(host) -> StatModifier:
	var b: StatBoard = host.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(&"armor")
	if s == null:
		return null
	for m in s._modifiers:
		if m is ArmorBreakModifier:
			return m
	return null
