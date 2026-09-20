class_name CurseStatus
extends StatusDef

## Curse (#965, hub #952): every stack raises the least damage a hit can land
## on the node — one node-local `ADD_BASE` on `min_damage_taken`, `value ==
## power`, so 10 stacks turn a 1-damage hit at armor 100 into 13 on a floor of
## 3. Deals nothing itself (`projected_damage` stays the base's 0); halving
## decay and no cap are the authored def's knobs (`curse.tres`). It is the
## answer to the bunker: a negative Bulwark-style floor is pushed toward and
## past zero, so enough stacks take the heal flip away
## (`docs/design/damage_over_time.md` §The four members).
##
## Same shape and discipline as [ArmorBreakStatus] / [BlindnessStatus]: the
## def is shared and stateless, the per-node handle is FOUND by type and
## REPLACED on every write, never edited in place — a static modifier is
## SHARED between a live board and its shadow clone (`StatBoard._localize`
## copies only formula-bearing ones), so mutating a found modifier's `value`
## from a shadow resolve would write the live world before any [AttackRecord]
## replays (`.claude/rules/attack-timeline.md`). Remove + add lands on
## whichever board the [NodeCombat] owns and leaves the other alone.
##
## Unlike the two MULTIPLY statuses, an ADD_BASE handle has no public bin to
## walk — `ModifierBins` folds additive ops into a scalar — so [method _find]
## reads the stat's applied list directly, the same walk the stat-board
## visualizer does. A `Stat.find_modifier(pred)` accessor belongs to
## `stats_system/`, not to this def.


## Own type so a found modifier can be told apart from any other ADD_BASE on
## `min_damage_taken`, and UNSCALED so a stack is +1 floor at any allocation
## depth (#376 — the universal law would ladder an ADD_BASE with level, and
## would do so by mutating the shared instance).
class CurseModifier:
	extends StatModifier

	func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
		return StatModifier.UNSCALED


func _on_applied(host, power: float) -> void:
	_set_curse(host, power)


## Fires BEFORE decay lands; [param after] is the power the node is about to
## hold. At `after == 0` the slice removes the status right after this, and
## [method _on_removed] strips the modifier.
func _on_tick(host, _before: float, after: float) -> void:
	_set_curse(host, after)


func _on_removed(host) -> void:
	var m := _find(host)
	if m != null:
		host.remove_local_modifier(m)


func _set_curse(host, power: float) -> void:
	var old := _find(host)
	if old != null:
		host.remove_local_modifier(old)
	if power <= 0.0:
		return
	var m := CurseModifier.new()
	m.stat_id = &"min_damage_taken"
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = power
	host.add_local_modifier(m)


## The [CurseModifier] on [param node]'s local `min_damage_taken`, or null.
func _find(host) -> StatModifier:
	var b: StatBoard = host.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(&"min_damage_taken")
	if s == null:
		return null
	for m in s._modifiers:
		if m is CurseModifier:
			return m
	return null
