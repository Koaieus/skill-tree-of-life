@tool
@abstract
class_name DistanceScale
extends Resource

## Maps a distance to the VALUE an aura grants at that distance (#900).
##
## [b]It returns the value, not a multiplier.[/b] The third parameter is the
## authored value it is shaping — a leaf modifier's `value`, or a heal effect's
## `base` — so a library scale spells itself as `value * <its multiplier>` and
## an [ExpressionScale] can ignore `value` entirely (`5 - d` is the heal ramp:
## 5 at the core, 4 one hop out, …). Before #900 this returned the multiplier
## alone and [EffectContext] multiplied; the aura could then never express an
## absolute per-hop ladder, and `LinearScale` forced the rim ring to 0.
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
##
## [b]Whether a computed value is worth granting is not this class's call.[/b]
## A 0 (or a sign flip) is a legitimate result; [member AuraEffect.discard]
## decides whether it lands. See that enum's docs for the authoring recipes.

## The value to grant at [param distance]. [param value] is the authored number
## being shaped (a leaf modifier's `value`); a library scale returns
## `value * <multiplier>`, an [ExpressionScale] returns whatever its formula says.
@abstract func scale(distance: float, max_distance: float, value: float) -> float


## STUB (#943): the positional hook — see the real docstring once implemented.
func scale_at(distance: float, max_distance: float, value: float,
		_hops: float, _euclid: float, _relation: int) -> float:
	return scale(distance, max_distance, value)


func wants_hops() -> bool:
	return false


func wants_euclid() -> bool:
	return false


## An optional tooltip clause describing the shape, e.g. "falling off with
## distance". Never derived from a formula string — authored, like
## [StatFormula]'s `per_phrase`. [method AuraEffect.get_description] appends it.
@export var phrase: String = ""


## True when [method scale] actually reads `max_distance`. Default false.
##
## [AuraEffect] asks before taking an incremental topology path: a normalizing
## scale re-derives EVERY node's multiplier the moment membership moves the
## widest observed distance, even though the metric itself reports nothing
## moved — so it must fall back to a full recompute. The metric side answers
## the mirror-image question through [method DistanceMetric.dirties_on_membership_change].
func uses_bound() -> bool:
	return false
