class_name ArmorBreakStatus
extends StatusDef

## Armor Break (#877, hub #868 D3/D8 shape): each hit chips a tunable
## FRACTION of node-local `armor` away. `power` IS the fraction removed —
## `reapply = ACCUMULATE` in the authored def makes repeated hits additive on
## that fraction (two 20% hits leave 60% armor, never (1-0.2)^2 = 64%), so a
## fully broken node (`power == power_max == 1.0`) reaches exactly ×0 armor.
## Recovery is `decay_per_tick` per turn, same shape as everything else here.
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
## `power_max` above `1.0` is nonsense authoring — a multiplier past ×0 would
## mean armor BELOW zero, i.e. bonus damage taken. The owner's call
## (2026-09-14): guard the def, not the formula — a defensive `max(0, …)`
## would hide a misauthored def silently. So `_on_applied`/`_on_tick` push an
## error and refuse to plant/update the modifier while `power_max > 1.0`;
## the def is a no-op rather than a lie.

## Own type so a found modifier can be told apart from any other MULTIPLY on
## `armor`, and UNSCALED so a broken node's armor loss is not laddered by
## allocation depth (#376 — same rationale as Blindness's BlindModifier).
class ArmorBreakModifier:
	extends StatModifier

	func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
		return StatModifier.UNSCALED


func _on_applied(host, power: float) -> void:
	if not _power_max_is_sane():
		return
	_set_break(host, power)


## Fires BEFORE decay lands; [param after] is the power the node is about to
## hold. At `after == 0` the slice removes the status right after this, and
## [method _on_removed] strips the modifier.
func _on_tick(host, _before: float, after: float) -> void:
	if not _power_max_is_sane():
		return
	_set_break(host, after)


func _on_removed(host) -> void:
	var m := _find(host)
	if m != null:
		host.remove_local_modifier(m)


## `false` (and a pushed error) iff this def is misauthored with
## `power_max > 1.0` — a multiplier on `armor` above ×0 would mean bonus
## damage taken, never intended by "chip armor away".
func _power_max_is_sane() -> bool:
	if power_max > 1.0:
		push_error(
			"ArmorBreakStatus: power_max must be <= 1.0 (got %s) — a multiplier above ×0 armor is nonsense authoring"
			% power_max
		)
		return false
	return true


func _set_break(host, power: float) -> void:
	var old := _find(host)
	if old != null:
		host.remove_local_modifier(old)
	var m := ArmorBreakModifier.new()
	m.stat_id = &"armor"
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = 1.0 - clampf(power, 0.0, 1.0)
	host.add_local_modifier(m)


## The [ArmorBreakModifier] on [param node]'s local `armor`, or null.
func _find(host) -> StatModifier:
	var b: StatBoard = host.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(&"armor")
	if s == null:
		return null
	for m in s.bins.multipliers:
		if m is ArmorBreakModifier:
			return m
	return null
