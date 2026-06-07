@tool
class_name LinearFormula
extends StatFormula

## Single-source × coefficient formula.
## effective_value = source_stat.value × scale_per_point
##
## Covers the vast majority of scaling cases (e.g. "+2% vision_range per PER").
## Use ExpressionFormula when you need more than one source or nonlinear math.

@export var source_stat_id: StringName = &""
@export var scale_per_point: float = 1.0


func get_input_ids() -> Array[StringName]:
	return [source_stat_id]


func compute(board: StatBoard) -> float:
	var s := board.get_stat(source_stat_id)
	return float(s.get_value()) * scale_per_point if s != null else 0.0
