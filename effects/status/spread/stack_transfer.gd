class_name StackTransfer
extends RefCounted

## One move of raw stacks of a single [StatusDef] between two hosts — what a
## [StatusSpread] rule emits and [SpreadApplier] lands. [member to] null means
## the stacks are burned (voided), the only way a rule may dissipate; no
## transfer ever creates stacks. Plain fields only, so a record can carry it.

var from: NodeCombat
## Null = burned.
var to: NodeCombat
var amount: float = 0.0


func _init(p_from: NodeCombat = null, p_to: NodeCombat = null, p_amount: float = 0.0) -> void:
	from = p_from
	to = p_to
	amount = p_amount
