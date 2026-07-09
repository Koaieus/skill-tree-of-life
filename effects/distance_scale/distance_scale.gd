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
## unbounded. Scales that don't normalize (Flat, Proportional, Shell) ignore it.

@abstract func scale(distance: float, max_distance: float) -> float
