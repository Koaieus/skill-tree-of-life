## Tooltip V2 (#226) — pure geometry helper implementing Decision 4 of the
## swarmable spec: the derived trace terminus.
##
## `TraceRouter._pcb`'s closing leg is ALWAYS exactly cardinal (one axis lands
## flush on `to`). That guarantee is what makes the panel edge a line arrives
## at fully determined by the closing leg's direction, rather than something
## an author has to place by hand:
##
##   arriving rightward (closing leg moves +x) -> LEFT edge
##   arriving leftward  (closing leg moves -x) -> RIGHT edge
##   arriving downward  (closing leg moves +y) -> TOP edge
##   arriving upward    (closing leg moves -y) -> BOTTOM edge
##
## WHERE along that edge is derived too: the point nearest the trunk top
## (`from + trunk_dir * trunk_px`, the shared origin every trace in a fan
## leaves from), clamped to [0.1, 0.9] of the edge so the closing leg keeps a
## real perpendicular run instead of grazing a corner. So panel POSITION is the
## only authored quantity: [method derive_anchor] recomputes which edge + where
## on that edge every time it's called, from `from`, the panel's rect, and the
## router params already on the [FanTrace] ([member FanTrace.trunk_dir] /
## [member FanTrace.bend_start]) plus the driver's fan-wide
## [member FanAnchorDriver.trunk_length]. Move the panel in the editor, call
## this again next frame (see `fan_anchor_driver.gd`), and the anchor — and the
## edge it sits on — updates with zero re-authoring.
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

## The derived slide's window along an edge, as fractions of its length. Off
## the corners on both ends: a corner belongs to two edges at once, and a
## closing leg that lands on one reads as arriving along the edge rather than
## into it.
const SLIDE_MIN := 0.1
const SLIDE_MAX := 0.9

## Bounds the candidate<->actual iteration below. Two edges are ever in play
## (the tie is always between one horizontal and one vertical candidate), so
## a fixed point — when one exists — is found within 2 tries; further tries
## only exist to surface a genuine 2-cycle oscillation deterministically
## instead of by accident of loop position.
const _MAX_ITER := 4


## Solves one unit's terminus: WHERE it lands on the panel, and on which edge.
## Returns `{anchor: Vector2, edge: Edge}`.
##
## This is the entry point [FanAnchorDriver] uses; [method derive_anchor] is the
## same answer minus the edge, kept as its own function because it is also the
## pure anchor-only question a dozen tests ask directly.
##
## `params` is a [TraceRouter] param dict (see [method FanTrace.route_params]) —
## `trunk_dir`, `trunk` and `trunk_px` are read, so the trace must already carry
## the fan-wide trunk length when this is called. Nothing here is an output the
## driver writes back into those params, which is what makes re-solving every
## frame a fixed point.
static func solve_route(from: Vector2, panel_rect: Rect2, params: Dictionary) -> Dictionary:
	var trunk_dir: Vector2 = params.get("trunk_dir", Vector2(0.0, -1.0))
	if trunk_dir == Vector2.ZERO:
		trunk_dir = Vector2(0.0, -1.0)
	trunk_dir = trunk_dir.normalized()
	var trunk_frac: float = params.get("trunk", FanTrace.PHI_FRACTION)
	var trunk_px: float = params.get("trunk_px", 0.0)
	var anchor := derive_anchor(from, panel_rect, trunk_dir, trunk_frac, trunk_px)
	return {
		"anchor": anchor,
		"edge": _edge_of_route_to(from, anchor, trunk_dir, trunk_frac, trunk_px),
	}


## Returns the point on `panel_rect`'s boundary where a PCB trace from `from`
## (leaving along `trunk_dir` for `trunk_px` pixels — or, at 0, for
## `trunk_frac` of the span, as the router itself falls back to) ACTUALLY
## arrives, per the route [TraceRouter] itself would draw to get there — not
## an approximation of it. See the class doc for why a single guess from the
## rect's centre isn't enough.
##
## Per candidate edge the slide is the trunk top's projection onto that edge,
## clamped to [SLIDE_MIN, SLIDE_MAX]. With a fixed `trunk_px` the trunk top is
## a constant, so the only thing the iteration has to agree on is the edge.
static func derive_anchor(from: Vector2, panel_rect: Rect2, trunk_dir: Vector2, trunk_frac: float = FanTrace.PHI_FRACTION, trunk_px: float = 0.0) -> Vector2:
	var centre := panel_rect.get_center()
	var trunk_top := _trunk_top_of_route(from, centre, trunk_dir, trunk_frac, trunk_px)
	var edge := _edge_of_route_to(from, centre, trunk_dir, trunk_frac, trunk_px)
	for _i in range(_MAX_ITER):
		var anchor := _nearest_on_edge(edge, panel_rect, trunk_top)
		var actual := _edge_of_route_to(from, anchor, trunk_dir, trunk_frac, trunk_px)
		if actual == edge:
			return anchor
		edge = actual
	# Two candidate edges kept disagreeing with each other's own routed
	# result — a genuine 2-cycle (only possible right at the tie boundary,
	# where the panel needs more separation from the node on one axis). Land
	# on whichever candidate this loop last computed rather than looping
	# forever or crashing; a human moving the panel a few pixels resolves it.
	#
	# The returned point is still ON a real edge and the route still reaches
	# it — what got traded away is PERPENDICULARITY: the closing leg runs
	# alongside that edge instead of into it. That's tolerated rather than
	# warned about, because it's a legitimate resting place for synthetic
	# geometry (`test_fan_anchor.gd`'s up-and-right quadrant case lands here and
	# asserts the edge is still the correct one). What must not tolerate it is a
	# SHIPPED unit — `test_fan_scene.gd`'s self-consistency test is
	# the guard, and the fix there is authoring, not code: give the panel more
	# separation from the pin on the tied axis.
	return _nearest_on_edge(edge, panel_rect, trunk_top)


## Asks [TraceRouter] for the real route to `to` and reads off which edge its
## closing leg (the last segment — always cardinal, per `_pcb`'s own
## guarantee) arrives at. The single source of truth stays in TraceRouter;
## this never re-derives the diagonal/trunk/gable math itself. `trunk_px` goes
## through because the router picks its FAMILY by it — a hand-built dict
## without it describes a different line than the one on screen.
static func _edge_of_route_to(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float, trunk_px: float) -> FanAnchor.Edge:
	var pts := _route(from, to, trunk_dir, trunk_frac, trunk_px)
	var leg := pts[pts.size() - 1] - pts[pts.size() - 2] if pts.size() >= 2 else Vector2.ZERO
	if absf(leg.x) >= absf(leg.y):
		return Edge.LEFT if leg.x >= 0.0 else Edge.RIGHT
	return Edge.TOP if leg.y >= 0.0 else Edge.BOTTOM


## The trunk top of the route TraceRouter would draw to `to` — its second
## point. With a fixed `trunk_px` that is `from + trunk_dir * trunk_px` for
## every target; the router is still asked rather than the formula repeated so
## the fractional fallback (`trunk_px` 0) stays its arithmetic, not a copy.
static func _trunk_top_of_route(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float, trunk_px: float) -> Vector2:
	var pts := _route(from, to, trunk_dir, trunk_frac, trunk_px)
	return pts[1] if pts.size() >= 3 else from


static func _route(from: Vector2, to: Vector2, trunk_dir: Vector2, trunk_frac: float, trunk_px: float) -> PackedVector2Array:
	return TraceRouter.compute_trace_points(from, to, TraceRouter.Style.PCB, {
		"trunk": trunk_frac,
		"trunk_dir": trunk_dir,
		"trunk_px": trunk_px,
	})


## The point on `edge` nearest `target`, clamped to the [SLIDE_MIN, SLIDE_MAX]
## window of the edge: `target`'s y projected onto a vertical (LEFT/RIGHT)
## edge, its x onto a horizontal (TOP/BOTTOM) one.
static func _nearest_on_edge(edge: FanAnchor.Edge, rect: Rect2, target: Vector2) -> Vector2:
	var far := rect.position + rect.size
	match edge:
		Edge.LEFT:
			return Vector2(rect.position.x, _clamped_along(target.y, rect.position.y, far.y))
		Edge.RIGHT:
			return Vector2(far.x, _clamped_along(target.y, rect.position.y, far.y))
		Edge.TOP:
			return Vector2(_clamped_along(target.x, rect.position.x, far.x), rect.position.y)
		_:
			return Vector2(_clamped_along(target.x, rect.position.x, far.x), far.y)


static func _clamped_along(value: float, lo: float, hi: float) -> float:
	if hi <= lo:
		return lo
	var t := clampf((value - lo) / (hi - lo), SLIDE_MIN, SLIDE_MAX)
	return lerpf(lo, hi, t)


## The panel rect in the coordinate space `panel.position` lives in (i.e. its
## parent's local space — the same space [FanTrace.to_point] is authored in).
## Reads the skin Control's own (position, size) rather than assuming a
## symmetric envelope, so an off-centre skin still measures correctly.
##
## Sums every Control ancestor's `position` between the skin and `panel`
## rather than assuming the skin is a direct child — `panel_base.tscn` nests
## it under a `PanelContainer` (the auto-hugging envelope) alongside its
## `MarginContainer` sibling, one level deeper than [method FanPanel.get_skin]
## used to require.
static func panel_rect_of(panel: FanPanel) -> Rect2:
	var skin := panel.get_skin()
	if skin == null:
		return Rect2(panel.position, Vector2.ZERO)
	var offset := Vector2.ZERO
	var node: Node = skin
	while node != null and node != panel:
		if node is Control:
			offset += (node as Control).position
		node = node.get_parent()
	return Rect2(panel.position + offset, skin.size)


## True if `point` lies strictly inside `rect` — used by tests to assert a
## trace's intermediate points never overshoot into (or past) the panel it
## terminates at. Points exactly on the boundary (the anchor itself) are not
## "inside".
static func is_inside(point: Vector2, rect: Rect2) -> bool:
	return point.x > rect.position.x and point.x < rect.position.x + rect.size.x \
		and point.y > rect.position.y and point.y < rect.position.y + rect.size.y
