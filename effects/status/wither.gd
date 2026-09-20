class_name WitherStatus
extends StatusDef

## Wither (#966, hub #952): every stack plants a node-local MULTIPLY on
## `healing_received` of `1 - factor_per_stack × stacks`, UNCLAMPED and
## uncapped — at the authored 0.1, 10 stacks block healing and 20 make it
## ×−1. Below zero every heal on the node (turn regen, the core aura, a
## healing spell) lands as TRUE damage that never closes D-9's regen gate —
## [method NodeCombat.heal_damage]'s special case, owner (2026-09-20): "it
## ruins your healing to making you effectively undead". The def owns none
## of that arithmetic; it only sets the multiplier and lets the heal door do
## the rest. Stacks halve per tick (`DecayMode.FRACTION`, authored on the
## `.tres`) and the modifier is re-planted at the post-decay power.
##
## Same shared-stateless shape as [ArmorBreakStatus]: the per-node handle is
## FOUND, and every write REPLACES the found modifier — a static modifier is
## SHARED between a live board and its shadow clone, so mutating `value` from
## a shadow resolve would write the live world before any [AttackRecord]
## replays (`.claude/rules/attack-timeline.md`).

## Healing lost per stack — `0.1` means 10 stacks block healing outright and
## 20 invert it. A tuning knob on the def, never a constant in a formula.
@export var factor_per_stack: float = 0.1


## Own type so a found modifier can be told apart from any other MULTIPLY on
## `healing_received`, and UNSCALED so the loss is not laddered by
## allocation depth (#376 — same rationale as Blindness's / ArmorBreak's).
class WitherModifier:
	extends StatModifier

	func _local_scale_override(_old_al: int, _new_al: int) -> Variant:
		return StatModifier.UNSCALED


func _on_applied(node: NodeCombat, power: float) -> void:
	_set_wither(node, power)


## Fires BEFORE decay lands; [param after] is the power the node is about to
## hold. At `after == 0` the slice removes the status right after this, and
## [method _on_removed] strips the modifier.
func _on_tick(node: NodeCombat, _before: float, after: float) -> void:
	_set_wither(node, after)


func _on_removed(node: NodeCombat) -> void:
	var m := _find(node)
	if m != null:
		node.remove_local_modifier(m)


func _set_wither(node: NodeCombat, power: float) -> void:
	var old := _find(node)
	if old != null:
		node.remove_local_modifier(old)
	var m := WitherModifier.new()
	m.stat_id = &"healing_received"
	m.operation = StatModifier.Operation.MULTIPLY
	m.value = 1.0 - factor_per_stack * maxf(power, 0.0)
	node.add_local_modifier(m)


## The [WitherModifier] on [param node]'s local `healing_received`, or null.
func _find(node: NodeCombat) -> StatModifier:
	var b := node.board()
	if b == null:
		return null
	var s: Stat = b.get_stat(&"healing_received")
	if s == null:
		return null
	for m in s.bins.multipliers:
		if m is WitherModifier:
			return m
	return null
