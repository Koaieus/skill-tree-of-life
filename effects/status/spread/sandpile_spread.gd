class_name SandpileSpread
extends StatusSpread

## Stub — implementation follows the red test.

@export_range(1, 10) var burn: int = 1
@export_range(0, 10) var keep: int = 0
@export var max_topples: int = 4096


func threshold(field: StackField, n: NodeCombat) -> int:
	return field.masked_degree(n) + burn + keep


func stabilize(_field: StackField) -> ToppleResult:
	return ToppleResult.new()
