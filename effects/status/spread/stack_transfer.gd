class_name StackTransfer
extends RefCounted

## One move of raw stacks of a single [StatusDef] between two hosts — what a
## [StatusSpread] rule emits and [SpreadApplier] lands. [member to] null means
## the stacks are burned (voided), the only way a rule may dissipate; no
## transfer ever creates stacks. Holds live slices; a record maps `from` /
## `to` onto the slices' `stable_id`s on the wire — the record's job, not this
## class's.

var from: NodeCombat
## Null = burned.
var to: NodeCombat
var amount: float = 0.0
## The row both ends move: `(def.id, key)` ([method StatusDef.group_key]);
## `true` for a shared def.
var key: Variant = true


func _init(p_from: NodeCombat = null, p_to: NodeCombat = null, p_amount: float = 0.0,
		p_key: Variant = true) -> void:
	from = p_from
	to = p_to
	amount = p_amount
	key = p_key
