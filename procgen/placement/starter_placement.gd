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


## Returns one [StartingPoint] per contender. [param camp_sizes] is the
## roster's camp shape (procgen never sees a [Faction] — the level translates
## its [ParticipantRoster] into this shape). [param radius] is the resolved
## shape-mask radius ([GraphProcgen]'s `0.5 * min(aabb.size.x, .y)`, read
## after auto-scaling). [param min_dist] is `2 * node_radius + node_padding`.
##
## Return order is PARTICIPANT order — camp 0 member 0, camp 0 member 1,
## camp 1 member 0, ... — regardless of arrangement, so the caller can zip
## the result to participants by index. This is load-bearing.
func plan(
		_camp_sizes: Array[int],
		_radius: float,
		_min_dist: float,
		_rng: RandomNumberGenerator,
) -> Array[StartingPoint]:
	push_error("StarterPlacement.plan is abstract — override in a subclass")
	return []
