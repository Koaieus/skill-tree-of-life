class_name BladeArcDriver
extends BladeDriver

## Drives one particle on a circular arc around `center`. Default ease is
## sine-in-out: zero angular velocity at endpoints, peak at the apex.

var particle: int
var center: Vector2
var radius: float
var start_angle: float
var sweep: float
var duration: float
## Ease curve: float[0..1] -> float[0..1]. Default = sine-in-out.
@warning_ignore("shadowed_global_identifier")
var ease: Callable

func _init(
		particle_: int,
		center_: Vector2,
		radius_: float,
		start_angle_: float,
		sweep_: float = TAU,
		duration_: float = 1.2,
		ease_: Callable = Callable()) -> void:
	particle = particle_
	center = center_
	radius = radius_
	start_angle = start_angle_
	sweep = sweep_
	duration = duration_
	ease = ease_ if ease_.is_valid() else Callable(self, "_sine_in_out")


func apply(positions: PackedVector2Array, t: float) -> void:
	var f := clampf(t / duration, 0.0, 1.0) if duration > 0.0 else 0.0
	var eased: float = ease.call(f)
	var angle := start_angle + sweep * eased
	positions[particle] = center + Vector2.from_angle(angle) * radius


## The one `cos` left in a gameplay-adjacent path, and it is deliberate (#547).
## Every other transcendental was removed because derived stats are recomputed
## on each peer, so a libm disagreement in the last bits desyncs them. This one
## isn't: the blade's hit set and its ordering ride the `AttackRecord` the
## authority stamps, and a peer re-simulates the sweep only to DRAW it. A
## last-ulp difference here moves a particle, not a landing. It would have been
## a hard blocker under lockstep, which is part of why lockstep was rejected —
## so don't "fix" it, and equally don't start relying on it to agree across
## platforms.
func _sine_in_out(f: float) -> float:
	return 0.5 - 0.5 * cos(PI * f)
