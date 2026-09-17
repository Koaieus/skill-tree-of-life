@tool
class_name HopMetric
extends DistanceMetric

## Shortest-path edge count from the source, measured over the given mirror.
## One BOUNDED BFS for the whole set — shared across every hop-metric aura
## asking about the same (mirror, source) on the same topology generation via
## [AuraDistanceCache], since a walk this method does is one an entity may have
## several auras asking for at once (the Serpent's pair, both off the core)
## (#626).
##
## Pass an [EntityNavigator] to measure through owned territory only — that is
## what makes a Serpent's coil worth building, and what stops a path from
## shortcutting through enemy land.
##
## [b]Never a flood[/b] (#943): the walk stops at a hop cap. The caller that
## knows the reach passes it ([member AuraEffect.reach] when hop-based); with
## no tighter cap the SELECTED SET's size is the cap — a node that Q1 selected
## can't be farther than that along a path inside the set, and the aura never
## re-walks the world Q1 already filtered.

## Test seam: how often [method depths] was asked (the door [AuraEffect] opens
## only for a scale that [method DistanceScale.wants_hops]).
static var depths_call_count: int = 0
## Test seam: how many vertices the LAST actual walk assigned a depth to — the
## "bounded, never a flood" claim, measured.
static var last_walk_size: int = 0


## Hop depth of every node within [param max_hops] of [param source] over
## [param mirror] — the one door onto the cached walk, so a caller wanting hop
## facts beside its own metric ([AuraEffect] feeding `h` to a formula) never
## reaches into this class's BFS. Nodes past the cap or in another component
## are simply absent.
static func depths(source: SkillNode, mirror: GraphMirror, max_hops: int) -> Dictionary[SkillNode, float]:
	depths_call_count += 1
	if source == null or mirror == null:
		return {}
	return AuraDistanceCache.get_or_walk(mirror, source, max_hops, Callable(HopMetric, &"_walk").bind(source, mirror))


## [param hop_cap] is the reach's bound when the caller knows one; the default
## caps at [param nodes]'s size (see the class docs).
func distances(source: SkillNode, nodes: Array[SkillNode], mirror: GraphMirror, hop_cap: int = -1) -> Dictionary[SkillNode, float]:
	var out: Dictionary[SkillNode, float] = {}
	if source == null or mirror == null:
		return out
	var cap := hop_cap if hop_cap >= 0 else nodes.size()
	var all := depths(source, mirror, cap)
	for n in nodes:
		if all.has(n):
			out[n] = all[n]
	return out


## A topology change (allocate/deallocate) can shift the shortest path to
## anything beyond the changed node — the whole reason this metric needs the
## shared walk-and-diff rather than a per-node membership update. See
## [method EuclideanMetric.dirties_on_membership_change] for the metric that
## can safely answer false.
func dirties_on_membership_change() -> bool:
	return true


## The actual BFS, capped at [param max_hops], wrapped as a one-arg [Callable]
## for [method AuraDistanceCache.get_or_walk] to invoke on a cache miss (it may
## widen the cap to cover an earlier ask on the same generation). The cap comes
## FIRST because `bind` appends its arguments after the call-time one.
static func _walk(max_hops: int, source: SkillNode, mirror: GraphMirror) -> Dictionary[SkillNode, float]:
	var found: Dictionary[SkillNode, int] = mirror.nodes_within(source, maxi(max_hops, 0))
	var out: Dictionary[SkillNode, float] = {}
	for n in found:
		out[n] = float(found[n])
	last_walk_size = out.size()
	return out
