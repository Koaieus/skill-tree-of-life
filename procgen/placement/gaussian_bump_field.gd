@tool
class_name GaussianBumpField
extends ScalarField

## Sum of Gaussian bumps: `1.0 + Σ amplitude·exp(-d²/2σ²)` over `centers`. The
## `+1.0` baseline keeps it neutral where no bump reaches, so it composes
## multiplicatively with other fields the same way [RadialGradientField] does.
##
## `centers` is populated by a placement pass (random scatter, Poisson
## min-distance, or snap-to-node), not by this resource — same split as
## [RadialGradientField.outer_radius] being back-filled by [GraphProcgen].
## Keeps the field itself a dumb, testable sampler.

@export var centers: Array[Vector2] = []
@export var sigma: float = 50.0
@export var amplitude: float = 1.0


func sample(point: Vector2) -> float:
	var total := 1.0
	var denom := 2.0 * sigma * sigma
	if denom <= 0.0:
		return total
	for c in centers:
		var d := point.distance_to(c)
		total += amplitude * exp(-(d * d) / denom)
	return total
