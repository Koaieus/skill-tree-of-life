class_name CurlOperator
extends RefCounted

## Cyclone's propagation as a linear operator on directed edges: spectral radius
## by power iteration, no cast and no world. History-dependent rules (closing gain,
## momentum merge, the merge itself) are NOT in the matrix, so the radius is not a
## bound in either direction; it is exact on a tree.
## See docs/domain/curl-operator.md

## Power iteration stops when the L1 growth ratio moves less than this between
## consecutive applications.
const TOLERANCE := 1.0e-9
const MAX_ITERATIONS := 4000
## Below this L1 mass the iterate has collapsed: the operator is nilpotent on
## this terrain (every tree is) and ρ is exactly 0.
const COLLAPSE_FLOOR := 1.0e-30

var terrain: CurlTerrain
## `(u, v)` per directed-edge state, in state order.
var states: Array[Vector2i] = []
## `ranked_targets[s][r]` = the state a rank-`r` child of state `s` lands in.
var ranked_targets: Array[PackedInt32Array] = []


static func build(terrain_: CurlTerrain, clockwise: bool = true) -> CurlOperator:
	var op := CurlOperator.new()
	op.terrain = terrain_
	var n := terrain_.positions.size()
	var index_of := {}
	for u in n:
		for v in terrain_.adjacency[u]:
			index_of[u * n + v] = op.states.size()
			op.states.append(Vector2i(u, v))
	for s in op.states.size():
		var uv: Vector2i = op.states[s]
		var candidates := PackedVector2Array()
		for w in terrain_.adjacency[uv.y]:
			candidates.append(terrain_.positions[w])
		var ranked := Curl.rank_indices(
				terrain_.positions[uv.x], terrain_.positions[uv.y], candidates, clockwise)
		var targets := PackedInt32Array()
		for local in ranked:
			var w: int = terrain_.adjacency[uv.y][local]
			targets.append(int(index_of[uv.y * n + w]))
		op.ranked_targets.append(targets)
	return op


## One wave: `out = M · x`, where `x` is damage per directed-edge state.
func apply(x: PackedFloat64Array, coefficients: PackedFloat32Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(states.size())
	for s in states.size():
		var mass := x[s]
		if mass == 0.0:
			continue
		var targets := ranked_targets[s]
		var width := mini(targets.size(), coefficients.size())
		for r in width:
			var c := coefficients[r]
			if c <= 0.0:
				continue
			out[targets[r]] += mass * c
	return out


## Growth per wave in the limit — the operator's spectral radius, by power
## iteration on the L1 norm (legal because every entry is non-negative).
##
## Returns exactly 0.0 when the iterate collapses: on a tree the walk is
## non-backtracking with nowhere to rejoin, so `M` is nilpotent and the spell
## deals its seed plus a decaying fan and stops. That is the reading, not a
## numerical failure.
func spectral_radius(coefficients: PackedFloat32Array) -> float:
	if states.is_empty():
		return 0.0
	var x := PackedFloat64Array()
	x.resize(states.size())
	x.fill(1.0 / float(states.size()))
	var ratio := 0.0
	for it in MAX_ITERATIONS:
		var y := apply(x, coefficients)
		var norm := 0.0
		for value in y:
			norm += value
		if norm <= COLLAPSE_FLOOR:
			return 0.0
		var previous := ratio
		ratio = norm
		for i in y.size():
			y[i] /= norm
		x = y
		if it > 8 and absf(ratio - previous) < TOLERANCE * maxf(1.0, ratio):
			break
	return ratio


## What one cast does over `waves` hops, seeded on `target` as if the caster
## stood on its neighbour `from_index`: `[E_1, E_2, …]`, the total damage
## landing on wave `k` for a seed impact of 1.0.
##
## Seeding on a directed-edge state rather than "on a node" is not a
## simplification — it is what the resolver does. [method CycloneSpread._arrival_position]
## falls back to the cast-from node, so the opening fan is ranked from a real
## direction and the arrival edge is dropped, exactly like every later hop.
func wave_energies(
		from_index: int, target: int, coefficients: PackedFloat32Array, waves: int
) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var s := state_index(from_index, target)
	if s < 0:
		return out
	var x := PackedFloat64Array()
	x.resize(states.size())
	x[s] = 1.0
	for _w in waves:
		x = apply(x, coefficients)
		var norm := 0.0
		for value in x:
			norm += value
		out.append(norm)
	return out


func state_index(u: int, v: int) -> int:
	for s in states.size():
		if states[s] == Vector2i(u, v):
			return s
	return -1
