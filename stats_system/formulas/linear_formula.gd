@tool
class_name LinearFormula
extends StatFormula

## Pass-through formula — reads one source stat's value. The modifier's `value`
## field carries any scaling coefficient (effective = modifier.value * source.value),
## so "+2 vision_range per PER" is modifier.value=2 + LinearFormula(perception),
## and "+1% range per DEX" is modifier.value=1 + LinearFormula(dexterity).
##
## Use ExpressionFormula when you need more than one source or nonlinear math
## (e.g. `floor(strength / 10.0)`).

@export var source_stat_id: StringName = &""


func get_input_ids() -> Array[StringName]:
	return [source_stat_id]


func compute(board: StatBoard) -> float:
	var s := board.get_stat(source_stat_id)
	return float(s.get_value()) if s != null else 0.0
