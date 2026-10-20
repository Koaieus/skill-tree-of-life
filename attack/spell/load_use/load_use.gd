@tool
class_name LoadUse
extends Resource

## How a hit spends one intake row's **load** — the swappable part of an
## [AspectIntake] ([member AspectIntake.use]). Abstract: [PlantUse] lands it as
## the concept's status rider, [DetonateUse] spends it as a blast, [FuelUse]
## spends nothing (the load only shapes the spell). A row with no use takes
## its concept status's default ([method AspectIntake.use_for_status]).
## See docs/adr/0070-an-intake-rows-load-use-is-a-swappable-resource.md.


## Contribute [param amount] of [param status]'s concept to [param bag].
## [param row] is the concept's intake row, null for an infused concept the
## spell does not list; [param status] may be null (a concept with no status).
## Called once per concept whose load is above zero. The base spends nothing.
func spend(_row: AspectIntake, _status: StatusDef, _amount: int, _bag: LoadBag) -> void:
	pass


## The row's tooltip line. [param board] folds the attacker's stacks-per-hit
## stat the way the landing does; a [param read_node] folds through its live
## slice instead. [param row] always has a status here.
func describe(row: AspectIntake, board: StatBoard = null, read_node: SkillNode = null) -> String:
	return row.status().applies_line(board, float(row.innate), "; " + row.ingest_line(),
			OnHitEffect.read_slice(read_node))
