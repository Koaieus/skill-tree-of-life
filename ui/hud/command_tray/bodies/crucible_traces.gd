class_name CrucibleTraces
extends RefCounted

## Pure routing for the crucible's circuit traces, socket pad to readout line.
##
## Pairs come in display order: pair 0 feeds the topmost readout line and must
## leave the RIGHTMOST socket, each next pair one socket further left. Trace k
## drops straight down to its turn, [code]turn_step * (k + 1)[/code] below the
## lowest pad (the rightmost turns first), runs right to its riser, rises (or
## drops) to its line's height, then runs right into the anchor. Risers sit
## [code]riser_gap[/code] left of the leftmost anchor, trace 0's leftmost and
## each next one [code]turn_step[/code] further right.
##
## Why that nests: a later trace turns below every earlier turn, runs under
## every earlier riser, and rises right of them to a lower line, so no two
## polylines meet. Holds while every anchor sits above its turn and right of
## every pad — the body's layout (readout beside, the arc below the vessel).


## One polyline per (froms[k], tos[k]) pair; the shorter array bounds the count.
static func route(froms: PackedVector2Array, tos: PackedVector2Array,
		turn_step: float, riser_gap: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var n := mini(froms.size(), tos.size())
	if n == 0:
		return out
	var floor_y := froms[0].y
	var anchor_x := tos[0].x
	for k in n:
		floor_y = maxf(floor_y, froms[k].y)
		anchor_x = minf(anchor_x, tos[k].x)
	for k in n:
		var from := froms[k]
		var to := tos[k]
		var turn_y := floor_y + turn_step * (k + 1)
		var riser_x := anchor_x - riser_gap - turn_step * (n - 1 - k)
		var pts := PackedVector2Array([from, Vector2(from.x, turn_y),
				Vector2(riser_x, turn_y), Vector2(riser_x, to.y), to])
		out.append(_dedup(pts))
	return out


static func _dedup(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or not out[out.size() - 1].is_equal_approx(p):
			out.append(p)
	return out
