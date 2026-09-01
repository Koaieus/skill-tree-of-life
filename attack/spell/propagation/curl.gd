@tool
class_name Curl

## Handedness on a planar graph: ranks a node's neighbours by the turn a front
## makes to reach them, measured clockwise (or counter-clockwise) from the edge
## it arrived on.
##
## [b]Why this exists at all.[/b] A set of neighbours has no handedness — that
## is why a rotation-blind [FanAllStep] is perfectly symmetric, and why parity
## kept surfacing as Cyclone's mechanic (#699): parity is what is left over
## when the curl is missing. But the graph IS planar — procgen builds edges from
## a Delaunay triangulation and only ever prunes (docs/domain/procgen.md) — and
## a planar embedding carries a [b]rotation system[/b], the cyclic order of the
## edges incident to each vertex. That cyclic order is the handedness, and it is
## already sitting in the node positions for free.
##
## Rank 1 is the [i]sharpest[/i] turn in the chosen direction, which hugs the
## face the front is circling; ranks 2, 3, … are progressively wider turns that
## radiate outward. Feeding those ranks decaying damage coefficients is what
## makes circulation reinforce and offshoots diminish — see [CycloneStep].
##
## [b]No transcendental, deliberately.[/b] `atan2` is the obvious way to sort by
## angle and it is banned in gameplay code by
## [code].claude/rules/multiplayer-sync.md[/code] — peers recompute derived
## values rather than receive them, so a trig call is a desync waiting for a
## platform difference. [method pseudo_angle] is the standard "diamond angle":
## strictly monotone in the true angle, exact under the same float ops on every
## peer, and built from nothing but adds, a divide and a compare.


## A value in [code][0, 4)[/code] strictly increasing with the counter-clockwise
## angle of [code](dx, dy)[/code] from +X. Not an angle, and never converted to
## one — only ever compared against another [method pseudo_angle].
##
## Returns -1.0 for the zero vector, which is [b]not[/b] a legal rank: a
## self-loop is a neighbour at zero distance ([Graph] lists it twice for
## degree's sake) and it has no angular slot at all. Callers drop it.
static func pseudo_angle(dx: float, dy: float) -> float:
	var manhattan := absf(dx) + absf(dy)
	if manhattan <= 0.0:
		return -1.0
	var p := dx / manhattan
	return (3.0 + p) if dy < 0.0 else (1.0 - p)


## [param candidates] re-ordered by turn angle at [param node], measured from
## the direction back towards [param from_position] — the edge the front
## arrived on. Rank 0 of the result is the sharpest turn.
##
## The arrival edge itself scores exactly 0 and is [b]dropped[/b], which is what
## makes the curl non-backtracking by construction and is why Cyclone no longer
## composes a [BacktrackFilter]: a filter cannot express "except the way I came"
## for a merged front, but a ranking measured from that very edge never offers
## it in the first place.
##
## Ties (two neighbours on the same ray) keep their incoming order, which comes
## from [method Graph.get_neighbours] and is therefore identical on every peer.
static func rank(
		from_position: Vector2,
		node: SkillNode,
		candidates: Array[SkillNode],
		clockwise: bool = true) -> Array[SkillNode]:
	var origin := node.global_position
	var back := from_position - origin
	# A real arrival edge scores exactly 0 and gets dropped below. A DEGENERATE
	# one must not: with no direction to have come from there is no edge to
	# exclude, and dropping the zero-key candidate would silently delete a
	# neighbour that merely happens to lie along the fallback axis.
	var exclude_arrival := true
	if back.length_squared() <= 0.0:
		# Any fixed axis will do; it must only be the SAME one on every peer.
		back = Vector2.RIGHT
		exclude_arrival = false
	var keyed: Array = []
	for i in candidates.size():
		var nb: SkillNode = candidates[i]
		var d := nb.global_position - origin
		var forward := back.dot(d)
		var side := back.cross(d)
		var key := pseudo_angle(forward, -side if clockwise else side)
		if key < 0.0:
			continue  # zero-length: self-loop, no angular slot
		if exclude_arrival and key <= 0.0:
			continue  # the arrival edge itself
		keyed.append([key, i, nb])
	keyed.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[SkillNode] = []
	for entry in keyed:
		out.append(entry[2])
	return out
