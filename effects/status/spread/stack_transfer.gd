class_name StackTransfer
extends RefCounted

## One move of raw stacks of a single [StatusDef] between two hosts — what a
## [StatusSpread] rule emits and [SpreadApplier] lands. [member to] null means
## the stacks are burned (voided), the only way a rule may dissipate; no
## transfer ever creates stacks. Holds live slices; a record maps `from` /
## `to` onto the slices' `stable_id`s on the wire — the record's job, not this
## class's.

## A holder: a [NodeCombat] or an [EntityCombat] (a core pile) — the
## [StatusHost] duck type, so untyped.
var from
## Null = burned. A holder, as [member from].
var to
var amount: float = 0.0
## The row both ends move: `(def.id, key)` ([method StatusDef.group_key]);
## `true` for a shared def.
var key: Variant = true


func _init(p_from = null, p_to = null, p_amount: float = 0.0,
		p_key: Variant = true) -> void:
	from = p_from
	to = p_to
	amount = p_amount
	key = p_key
