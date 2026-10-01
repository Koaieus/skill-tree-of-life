class_name FractionDiffusion
extends DiffusionSpread

@export_range(0.01, 1.0, 0.01) var fraction: float = 1.0


func on_tick(_field: StackField) -> Array[StackTransfer]:
	return []
