class_name ToggleGatesCommandHandler
extends CommandHandler

## [ToggleGatesCommand] -> [method AllocationSystem.apply_gate_flip_recorded].
## Validate refuses an off-turn toggle, an empty or odd pair list, a pair naming
## no gate and a gate the actor cannot toggle, then STAMPS the stranded set from
## [method AllocationSystem.gate_flip_cascade] into the command before it
## confirms (authority only — validate never runs on a peer). Apply lands the
## stamped set; nobody re-walks.


func _validate(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	if ctx.turn_manager == null or ctx.turn_manager.current_entity != actor:
		return false
	var cmd := command as ToggleGatesCommand
	var gates := resolve_gates(cmd.pairs, ctx)
	if gates.is_empty():
		return false
	for g in gates:
		if not g.can_toggle(actor):
			return false
	var stranded: Array[int] = []
	for n in ctx.allocation_system.gate_flip_cascade(gates, actor):
		stranded.append(n.stable_id)
	cmd.stranded_ids = stranded
	return true


func _apply(command: Command, actor: Entity, ctx: CommandContext) -> bool:
	var cmd := command as ToggleGatesCommand
	var gates := resolve_gates(cmd.pairs, ctx)
	if gates.is_empty():
		return false
	ctx.allocation_system.apply_gate_flip_recorded(gates, actor,
			ctx.resolve_nodes(cmd.stranded_ids))
	return true


## `[from, to, …]` stable ids -> live gates, or [] if the list is empty, odd, or
## any pair names no gate — all-or-nothing, like the command itself.
static func resolve_gates(pairs: Array[int], ctx: CommandContext) -> Array[Gate]:
	var out: Array[Gate] = []
	if ctx.graph == null or pairs.is_empty() or pairs.size() % 2 != 0:
		return out
	for i in range(0, pairs.size(), 2):
		var gate := ctx.graph.gate_between(ctx.resolve_node(pairs[i]), ctx.resolve_node(pairs[i + 1]))
		if gate == null:
			return [] as Array[Gate]
		out.append(gate)
	return out
