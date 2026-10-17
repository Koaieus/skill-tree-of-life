class_name SpendRingCellCommandHandler
extends CommandHandler
## Validates a [SpendRingCellCommand] against [RingTable] (adjacency, unspent)
## and the actor's `ring_points` (affordable), then lands it through
## [method Entity.buy_ring_cell] with private copies of the cell's grants.
##
## [b]Queued like every board verb[/b] — never [method bypasses_queue]: the
## queue is the confirmed-command-down route, so the authority's confirm is what
## carries the spend to every peer, and a peer's intent opens the awaiting gate
## the host's confirm or refusal closes. Bypassing (as [PickLootCommandHandler]
## must, to dodge a deadlock) would apply on the authority and broadcast nothing.


func validate(command: Command, ctx: CommandContext) -> bool:
	return _legal_cell(command as SpendRingCellCommand, ctx) != null


func apply(command: Command, ctx: CommandContext) -> bool:
	var spend := command as SpendRingCellCommand
	var cell := _legal_cell(spend, ctx)
	if cell == null:
		return false
	var grants: Array[StatModifier] = []
	for m in cell.grants:
		grants.append(m.duplicate(true) as StatModifier)
	return ctx.resolve_actor(spend.entity_id).buy_ring_cell(cell.name, grants, cell.cost)


func _legal_cell(spend: SpendRingCellCommand, ctx: CommandContext) -> RingTable.Cell:
	if spend == null or ctx.ring_system == null:
		return null
	var table := ctx.ring_system.table()
	var actor := ctx.resolve_actor(spend.entity_id)
	if table == null or actor == null or actor.stat_board == null:
		return null
	var pool := actor.stat_board.ring_points
	var cell := table.cell(spend.cell)
	if pool == null or cell == null or not table.can_buy(actor.ring_spent, spend.cell):
		return null
	return cell if pool.available() >= cell.cost else null
