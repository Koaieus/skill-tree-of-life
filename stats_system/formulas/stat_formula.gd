@tool
@abstract
class_name StatFormula
extends Resource

## Abstract base for pluggable stat formulas used by DerivedModifierDef.
## A formula is stateless — it reads from the board it is given and returns
## a float. All binding/subscription state lives on DerivedModifierDef.

## Ids of all stats this formula reads. DerivedModifierDef subscribes to
## value_changed on each so the target stat can dirty itself automatically.
func get_input_ids() -> Array[StringName]:
	return []

## Compute and return the modifier value. Called from
## DerivedModifierDef.get_effective_value() every time the pipeline runs.
func compute(board: StatBoard) -> float:
	return 0.0
