class_name BlindnessStatus
extends StatusDef

## Blindness (#873, hub #868 D8): while it lasts, the node sees and senses
## less — one `MULTIPLY` on each of the node-local `vision_range` and
## `sensor_range`, at `lerp(1.0, blind_factor, power / power_max)`, so the
## fog closes in at full power and recovers linearly as the power decays.
##
## The def is shared and stateless, so the per-node handle is FOUND rather
## than stored: the modifiers are [BlindModifier]s, and the one on a node's
## stat is located by type in that stat's multiplier bin. A tick REPLACES the
## found modifier with a fresh one (never stacks, never edits in place): a
## static modifier is SHARED between a live board and its shadow clone
## (`StatBoard._localize` copies only formula-bearing ones), so writing a
## found modifier's `value` from a shadow resolve would mutate the live world
## before any [AttackRecord] replays. Remove + add lands on whichever board
## the [NodeCombat] owns and leaves the other alone.
##
## Sensor range is cut as-is by owner call (2026-09-14): PER scales it up and
## procgen rolls it on nodes, so a base-1 node sensing nothing while blinded
## is accepted — [VisionSystem]'s `int()` truncation stays.

const STAT_IDS: Array[StringName] = [&"vision_range", &"sensor_range"]

## The multiplier on `vision_range` / `sensor_range` at full power. The
## owner's knob (`blindness.tres`); no test pins the authored value.
@export var blind_factor: float = 0.5


## The node-local multiplier Blindness plants — its own type so it can be
## found again on a stateless def, and UNSCALED so a blinded node is not more
## or less blind for being allocated deeper (the universal local-scale law
## would otherwise ladder a MULTIPLY with allocation level, #376).
class BlindModifier:
	extends StatModifier

	func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
		return StatModifier.UNSCALED


func _on_applied(host, power: float) -> void:
	_set_factor(host, power)


## Fires BEFORE decay lands; [param after] is the power the node is about to
## hold. At `after == 0` the slice removes the status right after this, and
## [method _on_removed] strips the modifiers — the factor briefly reads 1.0
## in between, which is exactly the recovered value anyway.
func _on_tick(host, _before: float, after: float) -> void:
	_set_factor(host, after)


func _on_removed(host) -> void:
	for stat_id in STAT_IDS:
		var m := _find(host, stat_id)
		if m != null:
			host.remove_local_modifier(m)


## The multiplier for [param power] — `1.0` at zero, [member blind_factor]
## at [member power_max].
func factor_for(power: float) -> float:
	if power_max <= 0.0:
		return 1.0
	return lerpf(1.0, blind_factor, clampf(power / power_max, 0.0, 1.0))


func _set_factor(host, power: float) -> void:
	var f := factor_for(power)
	for stat_id in STAT_IDS:
		var old := _find(host, stat_id)
		if old != null:
			host.remove_local_modifier(old)
		var m := BlindModifier.new()
		m.stat_id = stat_id
		m.operation = StatModifier.Operation.MULTIPLY
		m.value = f
		host.add_local_modifier(m)


## The [BlindModifier] on [param node]'s local [param stat_id], or null.
func _find(host, stat_id: StringName) -> StatModifier:
	var b: StatBoard = host.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(stat_id)
	if s == null:
		return null
	for m in s.bins.multipliers:
		if m is BlindModifier:
			return m
	return null
