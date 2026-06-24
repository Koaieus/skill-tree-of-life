@tool
class_name ScalarField
extends Resource

## Scalar value over graph-local 2D space. Composes with [ShapeMask] but is
## independent of it — any field pairs with any shape. Used by [GraphProcgen]
## to modulate per-node modifier budget; the same primitive can power spawn
## weighting, fog density, etc. later.
##
## Convention: 1.0 is "neutral / no modulation". Values < 1 dampen, > 1 boost.
## Subclasses set their own ranges; callers clamp to taste.

func sample(_point: Vector2) -> float:
	return 1.0
