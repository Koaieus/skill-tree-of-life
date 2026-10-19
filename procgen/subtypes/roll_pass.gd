@tool
class_name RollPass
extends Resource

## One extra roll a [NodeSubtype] grants its nodes, on top of the budget draw.
## Spends no budget: a node runs it with probability [member chance] and, when
## it fires, makes ONE weighted pick (cost ignored) among the entries whose
## [member StatPool.passes] name [member id]. A pass with no eligible entry
## rolls nothing. See docs/domain/node-subtypes.md § Roll passes.

## The pass name pools opt into via [member StatPool.passes]. Never
## [constant StatPool.BUDGET_PASS] — the budget loop is not an extra pass.
@export var id: StringName = &""

## Per-node probability this pass fires. Tentative, easy to change (#1529).
@export_range(0.0, 1.0) var chance: float = 1.0
