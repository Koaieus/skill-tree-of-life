@tool
class_name RadialGradientField
extends ScalarField

## Linear (or curve-shaped) radial interpolation. Within `inner_radius` the
## value is fixed at `inner_value`; past `outer_radius` it's fixed at
## `outer_value`; between, t ∈ [0,1] is fed through `curve` if assigned, then
## lerps. Defaults pair with a centred [CircularShapeMask] zero-config.

@export var center: Vector2 = Vector2.ZERO
@export var inner_radius: float = 0.0
## When > 0, used verbatim. When ≤ 0, [GraphProcgen] fills this from the
## resolved shape mask (so an auto-scaled shape and the budget gradient stay
## in lockstep).
@export var outer_radius: float = 0.0
@export var inner_value: float = 0.5
@export var outer_value: float = 1.5
## Optional shaping curve over t ∈ [0,1]. Output is read at `curve.sample(t)`
## so use a 0..1 curve range; values outside still work but make the lerp
## extrapolate. Leave unset for a straight linear fade.
@export var curve: Curve


func sample(point: Vector2) -> float:
	var d := point.distance_to(center)
	var span := maxf(0.0001, outer_radius - inner_radius)
	var t := clampf((d - inner_radius) / span, 0.0, 1.0)
	if curve != null:
		t = curve.sample(t)
	return lerpf(inner_value, outer_value, t)
