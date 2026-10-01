class_name SpreadApplier
extends RefCounted

## Lands a [StatusSpread] rule's [StackTransfer] list — a pure static, like
## [OutcomeApplier]. Debits EVERY `from` first, then credits every non-null
## `to`, each through [method StatusHost.adjust_power]: the list is a set of
## simultaneous moves, never a chain, so no credit can be re-spent by a later
## debit in the same list. A null `to` burns its amount. Moving is not
## landing: no attacker fold, but `_on_applied` runs, so a def's planted
## modifiers follow the stacks. Every transfer moves [param def] — a field,
## and so a rule's output, is one def's. Each transfer names its slices, so
## [param _world] is the world they belong to — carried for the call shape a
## record replay will use, not read. A debit larger than its `from`'s row
## floors at 0 while the credit lands in full: conservation is the RULE's
## contract ([StatusSpread]), not re-checked here.
static func apply(def: StatusDef, transfers: Array[StackTransfer],
		_world: CombatWorld = null) -> void:
	if def == null:
		return
	for t in transfers:
		if t != null and t.from != null and t.amount > 0.0:
			_host(t.from).adjust_power(def, -t.amount)
	for t in transfers:
		if t != null and t.to != null and t.amount > 0.0:
			_host(t.to).adjust_power(def, t.amount)


## The slice's [StatusHost]. [NodeCombat] exposes no delegate for
## [method StatusHost.adjust_power] yet (outside this unit's files), so this
## is the one reach into its composition.
static func _host(n: NodeCombat) -> StatusHost:
	return n._status_host
