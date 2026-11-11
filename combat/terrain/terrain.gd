class_name Terrain
extends RefCounted

## Terrain arithmetic (`docs/domain/elements.md` § Terrain) — static, pure,
## integer only. A node's terrain is two ints on [NodeState]: the signed
## [member NodeState.terrain_t] (heat − cold) and [member NodeState.charge].
## Everything here derives from them at read time; nothing stores a band.
## T reads GRAPH degree (`docs/domain/degree.md`), never entity degree.
## The one writer is [method NodeCombat.add_terrain].

## Which int an element's count reads, and from which side.
enum Axis { NONE, HEAT, COLD, CHARGE }


## T: a count must pass `t_per_degree × graph_degree` to prime.
static func threshold(graph_degree: int) -> int:
	return TerrainRules.shared().t_per_degree * graph_degree


## The soft cap k × T; stacks past it are the overflow.
static func cap(graph_degree: int, k: int) -> int:
	return k * threshold(graph_degree)


## The axis [param element] counts on. Element has no polarity field, so the
## three v1 elements are named here by id: Fire is +t, Ice is −t, Lightning is
## Charge. An unknown element has no terrain.
static func axis_of(element: Element) -> Axis:
	if element == null:
		return Axis.NONE
	match element.id():
		&"fire":
			return Axis.HEAT
		&"ice":
			return Axis.COLD
		&"lightning":
			return Axis.CHARGE
	return Axis.NONE


## [param element]'s count on [param state]: Fire = max(t, 0), Ice = max(−t, 0),
## Lightning = charge.
static func count_of(state: NodeState, element: Element) -> int:
	match axis_of(element):
		Axis.HEAT:
			return maxi(state.terrain_t, 0)
		Axis.COLD:
			return maxi(-state.terrain_t, 0)
		Axis.CHARGE:
			return state.charge
	return 0


## True iff a write to [param a] can move [param b]'s count: Fire and Ice net
## on the one signed t; Charge stands alone.
static func shares_int(a: Element, b: Element) -> bool:
	var x := axis_of(a)
	var y := axis_of(b)
	if x == Axis.NONE or y == Axis.NONE:
		return false
	return (x == Axis.CHARGE) == (y == Axis.CHARGE)


## Write [param delta] stacks of [param element] into [param state]: Heat
## raises t, Cold lowers it, Charge is clamped at 0. Raw — only
## [method NodeCombat.add_terrain] calls this; it owns bands, index and signal.
static func write(state: NodeState, element: Element, delta: int) -> void:
	match axis_of(element):
		Axis.HEAT:
			state.terrain_t += delta
		Axis.COLD:
			state.terrain_t -= delta
		Axis.CHARGE:
			state.charge = maxi(state.charge + delta, 0)


## True iff [param state] carries any terrain (the live index's membership).
static func has_terrain(state: NodeState) -> bool:
	return state.terrain_t != 0 or state.charge > 0


## The highest of [param element]'s bands whose threshold [param count]
## passes — a band's threshold is `threshold_multiple × t`, or [param cap_]
## when `at_cap`. Null when the count passes none (≤ T: inert).
static func band_of(element: Element, count: int, t: int, cap_: int) -> ElementBand:
	if element == null:
		return null
	var out: ElementBand = null
	for band in element.bands:
		if band == null:
			continue
		var at := cap_ if band.at_cap else band.threshold_multiple * t
		if count > at:
			out = band
	return out


## Stacks past T (the primed excess).
static func excess(count: int, t: int) -> int:
	return maxi(count - t, 0)


## Stacks past the cap (the overflow, which burns off quickly — #1795).
static func overflow(count: int, cap_: int) -> int:
	return maxi(count - cap_, 0)
