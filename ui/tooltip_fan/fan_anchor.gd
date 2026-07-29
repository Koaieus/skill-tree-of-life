## Tooltip V2 (#226) — pure geometry helper implementing Decision 4 of the
## swarmable spec: the derived trace terminus.
##
## `TraceRouter._pcb`'s closing leg is ALWAYS exactly cardinal (one axis lands
## flush on `to`). That guarantee is what makes the panel edge a line arrives
## at fully determined by the closing leg's direction, rather than something
## an author has to place by hand:
##
##   arriving rightward (closing leg moves +x) -> LEFT edge centre
##   arriving leftward  (closing leg moves -x) -> RIGHT edge centre
##   arriving downward  (closing leg moves +y) -> TOP edge centre
##   arriving upward    (closing leg moves -y) -> BOTTOM edge centre
##
## So panel POSITION is the only authored quantity: [method derive_anchor]
## recomputes which edge + where on that edge every time it's called, from
## `from`, the panel's rect, and the router params already authored on the
## [FanTrace] ([member FanTrace.trunk_dir] / [member FanTrace.bend_start]).
## Move the panel in the editor, call this again next frame (see
## `fan_anchor_driver.gd`), and the anchor — and the edge it sits on — updates
## with zero re-authoring.
##
## SELF-CONSISTENCY, not a one-shot guess: the edge nearest the panel's
## CENTRE is only a candidate. Moving `to` from the centre to that edge's
## point changes `rem` (the remainder TraceRouter's own PCB math travels
## after the diagonal), which can flip which axis is actually dominant once
## you're AT the edge instead of at the centre — the "went too far and the
## line still swaps orientation" bug this decision exists to kill. So
## [method derive_anchor] asks [TraceRouter] itself (never a re-derived
## approximation of its math) what the ACTUAL closing leg of the route TO
## each candidate looks like, and iterates candidate -> actual -> candidate
## until they agree. Verified against a real shipped unit (#226's NodeStats
## panel) that a centre-only guess gets wrong.
class_name FanAnchor
extends RefCounted

enum Edge { LEFT, RIGHT, TOP, BOTTOM }

## Bounds the candidate<->actual iteration below. Two edges are ever in play
## (the tie is always between one horizontal and one vertical candidate), so
## a fixed point — when one exists — is found within 2 tries; further tries
## only exist to surface a genuine 2-cycle oscillation deterministically
## instead of by accident of loop position.
const _MAX_ITER := 4


## Returns the point on `panel_rect`'s boundary where a PCB trace from `from`
## (leaving along `trunk_dir`, breaking to 45° at `trunk_frac` of the trunk
## axis) ACTUALLY arrives, per the route [TraceRouter] itself would draw to
## get there — not an approximation of it. See the class doc for why a
## single guess from the rect's centre isn't enough.
static func derive_anchor(from: Vector2, panel_rect: Rect2, trunk_dir: Vector2, trunk_frac: float = FanTrace.PHI_FRACTION, slide: float = 0.5) -> Vector2:
	var edge := _edge_of_route_to(from, panel_rect.get_center(), trunk_dir, trunk_frac)
	for _i in range(_MAX_ITER):
		var anchor := _point_on_edge(edge, panel_rect, slide)
		var actual := _edge_of_route_to(from, anchor, trunk_dir, trunk_frac)
		if actual == edge:
			return anchor
		edge = actual
	# Two candidate edges kept disagreeing with each other's own routed
	# result — a genuine 2-cycle (only possible right at the tie boundary,
	# where the panel needs more separation from the node on one axis). Land
	# on whichever candidate this loop last computed rather than looping
	# forever or crashing; a human moving the panel a few pixels resolves it.
	#
	# At `slide` 0 or 1 the anchor IS a corner, which belongs to both edges at
	# once — so a 2-cycle there is not a failure to resolve, it's two equally
	# correct answers naming the same point. The fallback lands on the right
	# place either way.
	return _point_on_edge(edge, panel_rect, slide)


## Asks [TraceRouter] for the real route to `to` and reads off which edge its
## closing leg (the last segment — always cardinal, per `_pcb`'s own
## guarantee) arrives at. The single source of truth stays in TraceRouter;
## this never re-derives the diagonal/trunk math itself.
static func _edge_of_route_to(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float) -> FanAnchor.Edge:
	var pts := TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {
		"trunk": trunk_frac,
		"trunk_dir": trunk_dir,
	})
	var leg := pts[pts.size() - 1] - pts[pts.size() - 2] if pts.size() >= 2 else Vector2.ZERO
	if absf(leg.x) >= absf(leg.y):
		return Edge.LEFT if leg.x >= 0.0 else Edge.RIGHT
	return Edge.TOP if leg.y >= 0.0 else Edge.BOTTOM


## Where on `edge` the anchor sits. `slide` runs 0 → 1 along the edge in
## reading order — top→bottom for the vertical (LEFT/RIGHT) edges, left→right
## for the horizontal (TOP/BOTTOM) ones. 0.5 is the edge centre, i.e. the
## behaviour before `slide` existed; 0 and 1 are the edge's two corners.
##
## Which edge is derived (that's what guarantees the arrival leg is
## perpendicular to it); only WHERE along it is authored. So a unit that moves
## across the fan's centreline flips edges automatically and its slide stays
## meaningful — nothing needs re-authoring.
static func _point_on_edge(edge: FanAnchor.Edge, rect: Rect2, slide: float = 0.5) -> Vector2:
	var t := clampf(slide, 0.0, 1.0)
	var far := rect.position + rect.size
	match edge:
		Edge.LEFT:
			return Vector2(rect.position.x, lerpf(rect.position.y, far.y, t))
		Edge.RIGHT:
			return Vector2(far.x, lerpf(rect.position.y, far.y, t))
		Edge.TOP:
			return Vector2(lerpf(rect.position.x, far.x, t), rect.position.y)
		_:
			return Vector2(lerpf(rect.position.x, far.x, t), far.y)


## The panel rect in the coordinate space `panel.position` lives in (i.e. its
## parent's local space — the same space [FanTrace.to_point] is authored in).
## Reads the skin Control's own (position, size) rather than assuming a
## symmetric envelope, so an off-centre skin still measures correctly.
static func panel_rect_of(panel: FanPanel) -> Rect2:
	var skin := panel.get_skin()
	if skin == null:
		return Rect2(panel.position, Vector2.ZERO)
	return Rect2(panel.position + skin.position, skin.size)


## True if `point` lies strictly inside `rect` — used by tests to assert a
## trace's intermediate points never overshoot into (or past) the panel it
## terminates at. Points exactly on the boundary (the anchor itself) are not
## "inside".
static func is_inside(point: Vector2, rect: Rect2) -> bool:
	return point.x > rect.position.x and point.x < rect.position.x + rect.size.x \
		and point.y > rect.position.y and point.y < rect.position.y + rect.size.y
