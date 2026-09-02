@tool
@abstract
class_name DistanceScale
extends Resource

## Maps a distance to a scalar multiplier applied to an aura modifier's `value`.
##
## [b]Deliberately not called "falloff."[/b] The return is an unbounded scalar,
## not an attenuation. It may rise with distance (the Serpent's hop buff), fall
## (Bulwark), spike at exactly one ring (Halo), or deepen a negative modifier
## (the Ninja's armor debuff). "Falloff" would imply `<= 1` and monotonic
## decrease — precisely the constraint this abstraction must not have.
##
## Also not "Gradient": Godot ships a built-in [Gradient], and `Edge.gd` already
## carries one. Shadowing it in a `@tool` script is a live footgun.
##
## [b]Sign lives on the modifier, shape lives here.[/b] A negative `value` makes a
## debuff aura; a rising scale makes its magnitude grow with distance. The two
## compose freely, which is why this must stay direction-agnostic.
##
## [param max_distance] is the aura's reach bound in the same units, or -1.0 when
## unbounded. A scale that doesn't normalize ignores it — say so by leaving
## [method uses_bound] at its default.

@abstract func scale(distance: float, max_distance: float) -> float


## True when [method scale] actually reads `max_distance`. Default false.
##
## [AuraEffect] asks before taking an incremental topology path: a normalizing
## scale re-derives EVERY node's multiplier the moment membership moves the
## widest observed distance, even though the metric itself reports nothing
## moved — so it must fall back to a full recompute. The metric side answers
## the mirror-image question through [method DistanceMetric.dirties_on_membership_change].
func uses_bound() -> bool:
	return false
