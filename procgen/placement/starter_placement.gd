@tool
class_name StarterPlacement
extends Resource

## Picks starting-point anchors for every contender in a run, arranged
## relative to the roster's camp structure and reproducible from the run
## seed. Mirrors how [AllocationPolicy] / [WeightProfile] / [ShapeMask] are
## structured: an abstract Resource base, concrete geometry lives in a
## subclass (see [CampAnnulusStarters]). See #551.
##
## Wired onto [member GraphProcgenStartingPoints.starter_placement]: when set, it
## REPLACES [GraphProcgen]'s manual `starting_points` + `_place_random_starters`
## list wholesale, rather than augmenting it.
##
## [b]Deviates from #551's sketched 3-arg signature[/b] (`camp_sizes, radius,
## rng`) by inserting `min_dist`. The arc-clamp requirement in that same issue
## ("if GROUPED's computed member spacing would fall below `1.5 * min_dist`
## ... widen `camp_arc_span` at runtime") needs the caller's REAL `min_dist =
## 2 * node_radius + node_padding` — [GraphProcgen.generate] already holds it
## as a local a few lines above the call site. An authored copy on this
## resource (or its subclass) could drift from the config's actual spacing
## and silently re-enable the exact anchor-drop bug the clamp exists to
## prevent, so it is threaded through instead of duplicated.
##
## [b]Widened by #742[/b] with two more flat params — `mask` (needed for a
## random fill, and for viability validation) and `max_tries` (the bounded
## retry a rejection-sampled placement needs) — rather than a wrapped context
## object, matching this file's own established precedent above:
## [CampAnnulusStarters] receives but ignores both; [CenterCoreStarters]'s
## random fill needs both.

## Minimum spacing between starters, expressed as a MULTIPLIER of `min_dist`
## (the caller's real `2 * node_radius + node_padding`) rather than an
## absolute distance — "hops" in the sense that `1.0` means "just clear of
## overlap" and a higher value buys more breathing room. Authored PER
## INSTANCE (#742): both [CampAnnulusStarters]' arc clamp and
## [CenterCoreStarters]' random-fill rejection sampling read this through
## [method degrade_spacing], so a preset that wants tighter or looser spacing
## tunes ONE number regardless of which placement it authors. Default ~3; a
## single-spawn-ring preset (`CenterCoreStarters` on `first_level.tres`)
## authors 6-7 — with only one ring of room, spacing matters more.
@export var viability_radius: float = 3.0


## Returns one [StartingPoint] per contender. [param camp_sizes] is the
## roster's camp shape (procgen never sees a [Faction] — the level translates
## its [ParticipantRoster] into this shape). [param radius] is the resolved
## shape-mask radius ([GraphProcgen]'s `0.5 * min(aabb.size.x, .y)`, read
## after auto-scaling). [param min_dist] is `2 * node_radius + node_padding`.
## [param mask] is the resolved [ShapeMask] (`contains()` + `aabb()`).
## [param max_tries] bounds a rejection-sampled placement's retry loop.
##
## Return order is PARTICIPANT order — camp 0 member 0, camp 0 member 1,
## camp 1 member 0, ... — regardless of arrangement, so the caller can zip
## the result to participants by index. This is load-bearing.
func plan(
		_camp_sizes: Array[int],
		_radius: float,
		_min_dist: float,
		_rng: RandomNumberGenerator,
		_mask: ShapeMask = null,
		_max_tries: int = 200,
) -> Array[StartingPoint]:
	push_error("StarterPlacement.plan is abstract — override in a subclass")
	return []


## The spacing a placement algorithm should demand on try [param attempt] of
## [param max_attempts], degrading from the full `viability_radius * min_dist`
## ask down to the `min_dist` floor as attempts run out — a pure function of
## its inputs (never `rng`), so every peer walking the same attempt sequence
## lands on the same answer. Shared so [CampAnnulusStarters]' arc-clamp
## widening and [CenterCoreStarters]' rejection-sample retry degrade by the
## SAME curve rather than two hand-tuned ones. A single-shot caller (arc
## widening asks once, never retries) passes `attempt = 0, max_attempts = 1`
## and gets back the full ask, unattenuated.
func degrade_spacing(min_dist: float, attempt: int, max_attempts: int) -> float:
	var full := viability_radius * min_dist
	if max_attempts <= 1:
		return full
	var t := clampf(float(attempt) / float(max_attempts - 1), 0.0, 1.0)
	return lerpf(full, min_dist, t)
