class_name BladeState
extends RefCounted

## Pure descriptor handed to BladeSim. Constructed once per simulate() call.
## Mutates in place during stepping — positions advance, prev_positions
## get rewritten. Re-build before re-running if you need a fresh start.

var positions: PackedVector2Array
var prev_positions: PackedVector2Array
var inv_masses: PackedFloat32Array
var radii: PackedFloat32Array
## Inner-disk radius per particle, mirroring [member SkillNode.inner_radius] —
## the geometric companion to [member radii] (the outer radius). Sim-inert
## (no constraint reads it); carried purely so the visual layer can draw a
## blade node's disc + rim band matching the SkillNode it was built from.
var inner_radii: PackedFloat32Array
## Per-particle blade damage — the FULL per-contact amount for each vertex,
## not a delta. Zeroed in build(); the caller fills each slot from the source
## SkillNode's get_local_value(&"blade_damage") (which already merges the
## wielder's base + any node-local spike modifiers). Read directly by the hit
## sites — no base added on top.
var vertex_damage: PackedFloat32Array
var pivot_index: int = 0
var edges: Array[Vector2i] = []
var constraints: Array[BladeConstraint] = []


## Build a state from particle data and a list of edges. Seeds one
## BladeDistanceConstraint per edge (rest = initial distance, fully rigid).
## Callers can append further constraints after this returns.
##
## `inner_radii_` is optional — sim callers that never spawn visuals (fixtures,
## [MeleeAttackPlan]'s headless simulate) can omit it; it then mirrors
## `radii_` (inner == outer, i.e. no rim band), which [BladeCircle] draws as a
## flat fill rather than a degenerate zero-width stroke.
static func build(
		positions_: Array[Vector2],
		pivot_idx: int,
		edges_: Array[Vector2i],
		radii_: Array[float],
		inner_radii_: Array[float] = []) -> BladeState:
	var s := BladeState.new()
	s.positions = PackedVector2Array(positions_)
	s.pivot_index = pivot_idx
	s.edges = edges_
	s.radii = PackedFloat32Array(radii_)
	s.inner_radii = PackedFloat32Array(inner_radii_ if not inner_radii_.is_empty() else radii_)
	s.vertex_damage = PackedFloat32Array()
	s.vertex_damage.resize(positions_.size())  # zero-init; caller fills per-vertex
	s.inv_masses = PackedFloat32Array()
	s.inv_masses.resize(positions_.size())
	for i in positions_.size():
		s.inv_masses[i] = 0.0 if i == pivot_idx else 1.0
	for e in edges_:
		var rest := positions_[e.x].distance_to(positions_[e.y])
		s.constraints.append(BladeDistanceConstraint.new(e.x, e.y, rest))
	return s


## Hop count from the pivot to the farthest vertex, walking `constraints`
## (not `edges`) — a phantom brace (ClampAddon's weld) shortens the path a
## correction has to travel just as much as a real edge does, so the fidelity
## budget in [BladeSim] must see it too. One BFS, O(vertices + constraints);
## do not call this per-iteration or per-particle — [BladeSim.simulate] calls
## it once per resolve and reuses the result for the whole swing.
##
## Only [BladeDistanceConstraint] contributes adjacency (the sole concrete
## [BladeConstraint] today); a future constraint type that doesn't connect
## exactly two particles is invisible to this walk by construction.
func pivot_eccentricity() -> int:
	var adjacency: Dictionary = {}
	for c in constraints:
		if c is BladeDistanceConstraint:
			var dc := c as BladeDistanceConstraint
			adjacency.get_or_add(dc.a, [] as Array[int]).append(dc.b)
			adjacency.get_or_add(dc.b, [] as Array[int]).append(dc.a)
	var hops := {pivot_index: 0}
	var queue: Array[int] = [pivot_index]
	var max_hops := 0
	var qi := 0
	while qi < queue.size():
		var cur: int = queue[qi]
		qi += 1
		var h: int = hops[cur]
		if h > max_hops:
			max_hops = h
		for nb in adjacency.get(cur, [] as Array[int]):
			if not hops.has(nb):
				hops[nb] = h + 1
				queue.append(nb)
	return max_hops
