@tool
class_name Curve2DPath
extends ProjectilePath

## Samples a Godot [Curve2D] and maps its endpoints onto `origin → target`
## via similarity transform (scale + rotate). The curve is authored in
## arbitrary local space — e.g. drawn with a temporary [Path2D] in the
## VFX playground — then reused at any range/angle.
##
## If the curve is missing or degenerate (< 2 points), falls back to a
## straight lerp so a half-configured asset still flies.

@export var curve: Curve2D


func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2:
	# Pace first, geometry second — [member ProjectilePath.ease_curve] remaps
	# TIME only, and defaults to the exact identity (#670).
	t = eased(t)
	if curve == null or curve.point_count < 2:
		return origin.lerp(target, t)
	var ref_start := curve.get_point_position(0)
	var ref_end := curve.get_point_position(curve.point_count - 1)
	var ref_vec := ref_end - ref_start
	if ref_vec.length_squared() < 1e-6:
		return origin.lerp(target, t)
	var baked_len := curve.get_baked_length()
	if baked_len <= 0.0:
		return origin.lerp(target, t)
	var actual_vec := target - origin
	var scale := actual_vec.length() / ref_vec.length()
	var rot := actual_vec.angle() - ref_vec.angle()
	var raw := curve.sample_baked(clamp(t, 0.0, 1.0) * baked_len)
	var relative := raw - ref_start
	return origin + relative.rotated(rot) * scale
