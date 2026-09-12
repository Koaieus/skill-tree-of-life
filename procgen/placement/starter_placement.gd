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
	return _lerp_toward_floor(viability_radius * min_dist, min_dist, attempt, max_attempts)


## The spacing a camp-aware placement should demand between two ALREADY-PLACED
## points on try [param attempt] of [param max_attempts] — #758's fix for the
## bimodality [method degrade_spacing] alone couldn't prevent (an enemy
## opening right on top of the player, or nothing finding them at all).
##
## Owner, 2026-09-10: "camp-(not-camp) separation. halved for
## camp-(same-camp)".
##
## [param same_camp] false (any two starters in DIFFERENT camps): the full
## `viability_radius * min_dist` ask, EVERY attempt, never degrading. Per the
## #758 acceptance spec, this is the assertion that kills the bimodality — a
## cross-camp pair sitting inside each other's floor is exactly the dice roll
## this exists to remove, so nothing here is allowed to shrink it.
##
## [param same_camp] true: half that ask (never below `min_dist`, so the curve
## never starts under its own floor at a low `viability_radius`), still
## degrading toward `min_dist` on the same curve [method degrade_spacing]
## uses — the escape valve that lets a crowded shape place a large camp at
## all, paid for by the cross-camp guarantee above rather than by weakening it.
func required_spacing(min_dist: float, attempt: int, max_attempts: int, same_camp: bool) -> float:
	if not same_camp:
		return viability_radius * min_dist
	var full := maxf(min_dist, 0.5 * viability_radius * min_dist)
	return _lerp_toward_floor(full, min_dist, attempt, max_attempts)


## Remember which camp a point was placed FOR, on the point itself.
##
## [method CenterCoreStarters.plan] compares each candidate against the points
## already placed and needs each one's camp. Reading it as `camp_of[j]` — the
## participant-slot lookup — indexed by the OUTPUT position is correct only
## while the two indices agree, and they stop agreeing the moment a slot is
## skipped (which `plan` does, deliberately, when a contender is unplaceable:
## see `test_crowded_map_warns_when_cross_camp_floor_is_unsatisfiable`). After
## one skip every later output slot is offset, and a CROSS-camp pair reads as
## same-camp — halving the floor #758 added precisely to stop an enemy opening
## on top of you, in exactly the crowded map where that matters most.
##
## Stored in metadata rather than as an `@export` because it is a placement-time
## working fact, not authored content: a `.tres` StartingPoint has no camp, and
## the run's roster is what assigns one.
func _stamp_camp(point: StartingPoint, camp: int) -> void:
	point.set_meta(&"camp", camp)


## The camp of the point at [param slot] of an ALREADY-PLACED list — read off
## the point, never off a participant-slot lookup. See [method _stamp_camp].
##
## An unstamped point answers -1, i.e. UNKNOWN, which no real camp index
## equals — so a caller comparing `camp_of_placed(...) == my_camp` reads
## "different camp" and demands the full non-degrading spacing. That is the
## conservative direction on purpose: an unknown neighbour treated as a
## camp-mate would halve the very floor this exists to protect. Falling back to
## `slot` would be wrong as well as unsafe — the slot index only equals the
## camp when every camp has exactly one member (for `[2, 2]`, slot 2 is camp 1).
func camp_of_placed(placed: Array[StartingPoint], slot: int) -> int:
	if slot < 0 or slot >= placed.size():
		return -1
	var p := placed[slot]
	return p.get_meta(&"camp", -1) if p != null else -1


func _lerp_toward_floor(full: float, floor_dist: float, attempt: int, max_attempts: int) -> float:
	if max_attempts <= 1:
		return full
	var t := clampf(float(attempt) / float(max_attempts - 1), 0.0, 1.0)
	return lerpf(full, floor_dist, t)
