@tool
@abstract
class_name ProjectilePath
extends Resource

## How a [Projectile] moves from `origin` to `target` over normalised time.
##
## Pure path-shape — knows nothing about speed, timing, or visuals. The
## [Projectile] driver iterates `t` from 0→1 over its `flight_time` and calls
## [method evaluate] each frame for the world-space position.
##
## Concrete subclasses are Resources so they can be authored as `.tres`,
## inspector-tuned, and shared across attacks. See [BezierArcPath] (default
## quadratic-arc) and [Curve2DPath] (in-editor curve modelling).
##
## [b]Ease (#670).[/b] [Projectile] feeds a strictly LINEAR `t` — it is a clock,
## and it has no business deciding pacing. So per-spell motion personality
## (snap-in, heavy sag, a hang at the apex) had nowhere to live except a bespoke
## path subclass. [member ease_curve] is that knob, and it lives on the base so
## all five shipped paths inherit it for free: a caller runs `t` through
## [method eased] and gets the same geometry travelled at a different pace.
##
## [b]It is a remap of TIME, not of SHAPE.[/b] `eased(0) == 0` and `eased(1) == 1`
## for every value, so a path's endpoints are untouched and a coordinator's
## impact-on-the-beat alignment is untouched. Default [constant EASE_LINEAR]
## is the exact identity — nothing already shipped changes.

## Named pacing curves. Godot's own [method @GlobalScope.ease] exponent, given a
## name so nobody hand-picks a float here either.
enum Ease {
	## `t` unchanged. The default, and the only value that is bit-identical to
	## no ease at all.
	LINEAR,
	## Starts slow, arrives fast — a build, a wind-up, a gathering strike.
	IN,
	## Leaves fast, settles in — a snap-out, a released spring.
	OUT,
	## Slow at both ends, quick through the middle. The general "with weight"
	## reading, and what a heavy body wants.
	IN_OUT,
	## Quick at both ends with a hang in the middle — a projectile that lofts
	## and hovers before dropping. Reads as a heavy sag on an arc path.
	OUT_IN,
}

## Which named curve [method eased] applies. See [enum Ease].
@export var ease_curve: Ease = Ease.LINEAR
## How hard [member ease_curve] bites, 0 = none (identity, whatever the curve),
## 1 = the full named curve. A blend rather than a second exponent knob, so a
## curve stays recognisably itself at every strength.
@export_range(0.0, 1.0, 0.05) var ease_strength: float = 1.0


## World-space position at normalised time [param t] (0 = origin, 1 = target).
## Implementations should be deterministic and pure — same inputs → same output.
##
## Implementations that want the ease knob call [method eased] on their incoming
## `t` first; the shipped five all do.
@abstract func evaluate(t: float, origin: Vector2, target: Vector2) -> Vector2


## [param t] remapped through [member ease_curve] at [member ease_strength].
##
## Pinned properties, asserted in `test/unit/vfx/test_projectile_path_ease.gd`:
## the endpoints are fixed (`eased(0) == 0`, `eased(1) == 1`), the result is
## monotonic (a projectile never travels backwards), and [constant Ease.LINEAR]
## — or strength 0 — returns `t` unchanged, bit for bit.
func eased(t: float) -> float:
	var k: float = clampf(t, 0.0, 1.0)
	if ease_curve == Ease.LINEAR or ease_strength <= 0.0:
		return k
	var shaped: float = _shape(k)
	return lerpf(k, shaped, clampf(ease_strength, 0.0, 1.0))


## The named curve at full strength. Deliberately arithmetic — no `pow`, no
## transcendental. `.claude/rules/multiplayer-sync.md` bans those in gameplay
## code and stat formulas; a VFX path is neither, but the cheap polynomial forms
## below are exactly as expressive here and cost nothing to prefer.
func _shape(k: float) -> float:
	match ease_curve:
		Ease.IN:
			return k * k
		Ease.OUT:
			var u: float = 1.0 - k
			return 1.0 - u * u
		Ease.IN_OUT:
			if k < 0.5:
				return 2.0 * k * k
			var u2: float = 1.0 - k
			return 1.0 - 2.0 * u2 * u2
		Ease.OUT_IN:
			# The mirror of IN_OUT: fast off both ends, a hang in the middle.
			var c: float = 2.0 * k - 1.0
			return 0.5 + 0.5 * c * c * signf(c)
		_:
			return k
