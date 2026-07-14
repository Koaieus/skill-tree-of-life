@tool
class_name CompositeField
extends ScalarField

## Folds `children` into one value via `mode`. Lets a designer stack e.g. an
## uphill [RadialGradientField] + scattered [GaussianBumpField] + a
## [NoiseField] into the single `budget_field` lever [BudgetPolicy] exposes.

enum Mode { SUM, MAX, MUL }

@export var children: Array[ScalarField] = []
@export var mode: Mode = Mode.MUL


func sample(point: Vector2) -> float:
	var acc := 0.0 if mode == Mode.SUM else (1.0 if mode == Mode.MUL else -INF)
	var any := false
	for child in children:
		if child == null:
			continue
		any = true
		var v := child.sample(point)
		match mode:
			Mode.SUM:
				acc += v
			Mode.MUL:
				acc *= v
			Mode.MAX:
				acc = maxf(acc, v)
	return acc if any else 1.0
