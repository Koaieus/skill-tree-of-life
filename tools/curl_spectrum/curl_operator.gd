class_name CurlOperator
extends RefCounted

## Cyclone's propagation as a [b]linear operator on directed edges[/b] (#705).
##
## Keep the walk's state on the edge it arrived along rather than on the node it
## stands at, and [CycloneStep] becomes a fixed non-negative matrix: a front in
## state `(u → v)` mints one child per turn-rank `r`, in state `(v → w_r)`,
## carrying `rank_coefficients[r]` of its damage. Damage is conserved-then-
## scaled and [CycloneReducer] SUMS on convergence, so total damage per wave is
## exactly `‖M^k x‖₁` — and growth per wave is `M`'s spectral radius, by power
## iteration, with no cast and no world.
##
## [b]What the linear model leaves out, and which way it errs.[/b] Three of the
## shipped spell's rules are history-dependent and so cannot be a matrix entry:
## [codeblock]
## closing_gain      — needs the front's trail to know a hop closes a ring
## momentum merge    — the merged heading re-aims the NEXT ranking
## the merge itself  — N incidents become ONE front, which then fans ONCE
## [/codeblock]
## The third is the one that bites, and it is not a rounding error: where the
## operator keeps two converging fronts as two directed-edge states that each
## fan in full, the resolver collapses them into a single payload that fans
## once, so convergence [i]loses[/i] arms even while it sums damage.
##
## So ρ is [b]not[/b] a bound in either direction, and #705 measured which way
## it misses rather than assuming: against real [SpellResolver] casts on the
## same terrain, the walk tracks the operator exactly for two waves, then runs
## BELOW it on sparse ground (merge-collapse dominates) and ABOVE it on dense
## ground once `closing_gain` starts firing — roughly ±30% by wave 8 at the
## shipped 0.25 connectivity. Table E of `snapshot.md` is that comparison, and
## it is why the sweep ships a cast probe instead of a footnote.
##
## What ρ [i]is[/i] exact for is the question the floor rests on: a tree, where
## nothing ever closes and nothing ever merges, reads 0.000 and the two models
## agree term by term.
##
## The ranking itself is NOT re-derived here: [method Curl.rank_indices] is the
## same call the shipped step makes.

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
## simplification — it is what the resolver does. [method CycloneStep._arrival_position]
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
