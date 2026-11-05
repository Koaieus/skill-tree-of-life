@tool
@abstract
class_name DistanceScale
extends Resource

## Maps a distance to the VALUE an aura grants there. Returns the value, not a
## multiplier (the third parameter is the authored value being shaped). Not called
## "falloff" or "gradient". Sign lives on the modifier, shape here; whether a
## result lands is `AuraEffect.discard`'s call.
## See docs/domain/effect-system.md

## The one result that is NOT a value: "no modifier here". NaN, so no
## comparison the discard policy could make is ever true of it — [AuraEffect]
## drops a [constant NOT_GRANTED] leaf before [member AuraEffect.discard] runs,
## under every mode. Test for it with `is_nan()`, never `==`: NaN is not equal
## to itself. Library shapes never return it; an [ExpressionScale] does by
## writing `NAN` (a built-in [Expression] constant), and a per-hop table past
## its last entry will.
const NOT_GRANTED := NAN

## The value to grant at [param distance]. [param value] is the authored number
## being shaped (a leaf modifier's `value`); a library scale returns
## `value * <multiplier>`, an [ExpressionScale] returns whatever its formula says.
@abstract func scale(distance: float, max_distance: float, value: float) -> float


## The positional hook (#943): the same value as [method scale], with three
## more facts about the node the aura's metric did not measure —
## [param hops] (shortest-path edge count from the source over the aura's
## mirror, `-1.0` when the node is in another component or the walk was not
## asked for), [param euclid] (pixels from the source, `-1.0` when not asked
## for) and [param relation] (the node's [enum SkillNode.Ownership] bit as
## the aura's owner sees it: NEUTRAL 1, MINE 2, ALLY 4, HOSTILE 8).
##
## No class, no lens: the owner's call was a positional hook, since a
## `NodeRelation` view would hold nothing but the two nodes. The library
## shapes never override this — only [ExpressionScale] does, because only a
## formula can name `h`, `e` or `rel`. [AuraEffect] pays for [param hops] /
## [param euclid] only when [method wants_hops] / [method wants_euclid] say so.
func scale_at(distance: float, max_distance: float, value: float,
		_hops: float, _euclid: float, _relation: int) -> float:
	return scale(distance, max_distance, value)


## True when [method scale_at] reads its `hops` argument — the aura walks hop
## depths (a bounded BFS, [method HopMetric.depths]) only for a scale that
## says so. Default false; [ExpressionScale] answers from the formula text.
func wants_hops() -> bool:
	return false


## True when [method scale_at] reads its `euclid` argument — one
## `distance_to` per selected node, skipped otherwise. Default false.
func wants_euclid() -> bool:
	return false


## True when one [method scale_at] call is worth caching per distinct input
## tuple for the length of a grant pass — an [ExpressionScale] evaluation is,
## a closed-form library shape is cheaper than the lookup. Default false; a
## scale reading continuous `euclid` answers false too, since nothing repeats.
func memoizable() -> bool:
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
