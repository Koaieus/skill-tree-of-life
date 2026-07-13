class_name BladeState
extends RefCounted

## Pure descriptor handed to BladeSim. Constructed once per simulate() call.
## Mutates in place during stepping — positions advance, prev_positions
## get rewritten. Re-build before re-running if you need a fresh start.

var positions: PackedVector2Array
var prev_positions: PackedVector2Array
var inv_masses: PackedFloat32Array
var radii: PackedFloat32Array
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
static func build(
		positions_: Array[Vector2],
		pivot_idx: int,
		edges_: Array[Vector2i],
		radii_: Array[float]) -> BladeState:
	var s := BladeState.new()
	s.positions = PackedVector2Array(positions_)
	s.pivot_index = pivot_idx
	s.edges = edges_
	s.radii = PackedFloat32Array(radii_)
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
