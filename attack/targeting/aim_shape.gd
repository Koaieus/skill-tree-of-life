@tool
@abstract
class_name AimShape
extends Resource

## The geometry an [AimedTargeting] sweeps from its cast-from node: which nodes
## a shape pointed at [code]angle[/code] (radians) out to [code]length[/code]
## pixels crosses. Pure geometry — no ownership, no reach scaling; the
## targeting folds those in around [method crossed].
##
## A node counts when any part of its disc touches the shape — the same disc
## semantics [method EuclideanRangeFinder._reaches] uses for range, so a
## stake-grown node is easier to hit here too.

## Caps the crossed set, nearest-first. 0 = no cap: the shape passes through
## everything it touches.
@export_range(0, 64, 1, "or_greater") var max_hits: int = 0


## Every node in [param nodes] whose disc touches the shape, sorted by centre
## distance from [param origin] (ties by [member SkillNode.stable_id], so the
## order never depends on the order [param nodes] came in) and capped at
## [member max_hits]. One linear pass over [param nodes] — hand it a narrowed
## candidate set ([method reach]), never the whole board.
func crossed(origin: Vector2, angle: float, length: float, nodes: Array[SkillNode]) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if length <= 0.0:
		return out
	var dir := Vector2.from_angle(angle)
	for n in nodes:
		if n != null and _touches(origin, dir, length, n):
			out.append(n)
	out.sort_custom(func(a: SkillNode, b: SkillNode) -> bool:
		var da := origin.distance_squared_to(a.global_position)
		var db := origin.distance_squared_to(b.global_position)
		return da < db or (da == db and a.stable_id < b.stable_id))
	if max_hits > 0 and out.size() > max_hits:
		out.resize(max_hits)
	return out


## The radius around the origin that bounds the shape at [param length]: any
## node whose disc touches the shape has its centre within
## `reach + node.radius` of the origin — the circle a grid gather narrows by.
@abstract func reach(length: float) -> float


## True iff [param node]'s disc touches this shape, anchored at
## [param origin] and pointing along the unit vector [param dir].
@abstract func _touches(origin: Vector2, dir: Vector2, length: float, node: SkillNode) -> bool
